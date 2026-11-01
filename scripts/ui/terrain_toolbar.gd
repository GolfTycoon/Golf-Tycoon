extends PanelContainer
class_name TerrainToolbar
## Three dock sections share one horizontally scrolling shelf. Tool selection
## and keyboard shortcuts reveal the owning section and its circular tab.
## Player edit/skills share PlayerTab's persistent view so a live round is never
## rebuilt or interrupted by navigation.

signal section_changed(section: int)
## Emitted when the whole section shelf is hidden (false) or shown again (true).
signal section_visibility_changed(open: bool)
signal financial_overview_pressed
signal course_review_pressed
signal tool_selected(tool_type: int)
signal open_hole_pressed
signal building_placement_pressed
signal building_selected(building_type: String)
signal decoration_placement_pressed
signal decoration_selected(decoration_type: String)
signal elevation_tool_pressed(tool_name: String)
signal elevation_brush_size_changed(new_size: int)
signal elevation_brush_shape_changed(square_shape: bool)
signal bulldozer_pressed
## The pinned Inspect toggle on a Build tab was switched on (true) or off.
signal inspect_toggled(enabled: bool)
signal brush_size_changed(new_size: int)
signal brush_shape_changed(round_shape: bool)
signal play_course_pressed
signal tournaments_pressed
## Buy, browse and switch between the company's course sites on the world map.
signal world_map_pressed
## The company's live course as one isometric map: land, holes, aura and staff.
signal course_map_pressed
## The Holes tab's shortcut to that map, opened on the mode that is about
## the holes themselves: Routing Holes.
signal holes_map_pressed
## The Club tab's Review entry now opens the Course Map on Aura, where the
## full Course Review lives.
signal aura_map_pressed
## Hole management actions emitted from the Holes tab's hole detail view.
signal hole_move_tee_requested(hole_number: int)
signal hole_move_green_requested(hole_number: int)
signal hole_toggle_requested(hole_number: int)
signal hole_par_override_requested(hole_number: int, new_par: int)
signal hole_delete_requested(hole_number: int)
signal hole_locate_requested(hole_number: int)
signal hole_detail_changed(hole_number: int)
## The Staff tab's shortcut to that map, opened on the mode that is about
## the crew: Staff.
signal staff_map_pressed
signal marketing_pressed
## The Club tab's Feed card: the course event feed (also the N hotkey).
signal event_feed_pressed
## The Feed card's unread count changed, so the dock can light the same
## count on its Manage section button.
signal feed_unread_count_changed(count: int)
signal course_milestones_pressed
signal world_milestones_pressed
signal achievements_pressed
signal golfer_row_clicked(golfer_id: int)
## Ask main.gd to start (index >= 0) or cancel (index < 0) repositioning a staff
## member's designated area.
signal staff_area_move_requested(staff_index: int)

enum Tab { TERRAIN, IMPROVEMENTS, BUILDINGS, ELEVATION, HOLES, GOLFERS, PLAYER, CLUB, STAFF, EDIT_PLAYER, PLAYER_SKILLS }
enum Section { BUILD, MANAGE, GOLFERS }
const SECTION_TITLES := ["Build", "Manage", "Golfers"]
const SECTION_COLORS := [Color("d8bb71"), Color("8dba9b"), Color("87b9cf")]
const SECTION_TABS := {
	Section.BUILD: [Tab.TERRAIN, Tab.IMPROVEMENTS, Tab.BUILDINGS, Tab.ELEVATION],
	Section.MANAGE: [Tab.CLUB, Tab.HOLES, Tab.STAFF],
	Section.GOLFERS: [Tab.GOLFERS, Tab.PLAYER, Tab.EDIT_PLAYER, Tab.PLAYER_SKILLS],
}
const TAB_TITLES := {
	Tab.TERRAIN: "Terrain", Tab.IMPROVEMENTS: "Improvements",
	Tab.BUILDINGS: "Buildings", Tab.ELEVATION: "Elevations", Tab.HOLES: "Holes",
	Tab.GOLFERS: "Visiting Golfers", Tab.PLAYER: "Play Course", Tab.CLUB: "Club",
	Tab.STAFF: "Staff", Tab.EDIT_PLAYER: "Edit Player Golfer",
	Tab.PLAYER_SKILLS: "Player Golfer Skills",
}
const TAB_ICONS := ["terrain", "improvements", "buildings", "elevation", "holes",
	"golfers", "play", "club", "staff", "edit", "skills"]
const PLAYER_TABS := [Tab.PLAYER, Tab.EDIT_PLAYER, Tab.PLAYER_SKILLS]
const HEADER_HEIGHT := 28.0
## The tabs occupy a mirrored arc to the left of the scrolling pages, and the
## pages reach in under them (see ShelfPageWindow). On a narrow phone the rail
## gives up width before the pinned page controls do.
const SHELF_PAD_X := 6.0
const SHELF_PAD_Y := 2.0
## Vertical offset of the header row from the shelf's top edge: negative so
## the top of the circular tool buttons rises above the shelf border.
const HEADER_ROW_TOP_OFFSET := -13.0
const SHELF_ROW_GAP := 6.0
## Breathing room kept before the first object in every scrollable shelf page,
## so the first tile/card never rubs against the curved rim at the shelf's
## left edge.
const SHELF_CONTENT_LEAD := 80.0
## Together with the 6px inset this matches the left fan's 224px radius.
## Compact windows shorten it only as much as the page needs to stay usable.
const TAB_RAIL_WIDTH := 218.0
const TAB_RAIL_MIN_WIDTH := 58.0
## A 52px brush plate plus its 10px corner margin must fit even on a phone.
const SHELF_BODY_MIN_WIDTH := 62.0
const TAB_RAIL_GAP := 2.0

const TOOL_TAB_MAP := {
	TerrainTypes.Type.TEE_BOX: Tab.TERRAIN,
	TerrainTypes.Type.GREEN: Tab.TERRAIN,
	TerrainTypes.Type.BUNKER: Tab.TERRAIN,
	TerrainTypes.Type.ROUGH: Tab.TERRAIN,
	TerrainTypes.Type.POT_BUNKER: Tab.TERRAIN,
	TerrainTypes.Type.STREAM: Tab.TERRAIN,
	TerrainTypes.Type.WATER: Tab.TERRAIN,
	TerrainTypes.Type.FAIRWAY: Tab.TERRAIN,
	TerrainTypes.Type.FIRM_FAIRWAY: Tab.TERRAIN,
	TerrainTypes.Type.DEEP_ROUGH: Tab.TERRAIN,
	TerrainTypes.Type.WASTE_BUNKER: Tab.TERRAIN,
	TerrainTypes.Type.BRUSH: Tab.TERRAIN,
	TerrainTypes.Type.ROCKS: Tab.TERRAIN,
	TerrainTypes.Type.SMALL_BOULDERS: Tab.TERRAIN,
	TerrainTypes.Type.LARGE_BOULDERS: Tab.TERRAIN,
	TerrainTypes.Type.OUT_OF_BOUNDS: Tab.TERRAIN,
	TerrainTypes.Type.TREES: Tab.TERRAIN,
	TerrainTypes.Type.OAK: Tab.TERRAIN,
	TerrainTypes.Type.PINE: Tab.TERRAIN,
	TerrainTypes.Type.MAPLE: Tab.TERRAIN,
	TerrainTypes.Type.BIRCH: Tab.TERRAIN,
	TerrainTypes.Type.CACTUS: Tab.TERRAIN,
	TerrainTypes.Type.FESCUE: Tab.TERRAIN,
	TerrainTypes.Type.CATTAILS: Tab.TERRAIN,
	TerrainTypes.Type.SHRUB: Tab.TERRAIN,
	TerrainTypes.Type.PALM: Tab.TERRAIN,
	TerrainTypes.Type.DEAD_TREE: Tab.TERRAIN,
	TerrainTypes.Type.HEATHER: Tab.TERRAIN,
	"open_hole": Tab.TERRAIN,
	TerrainTypes.WALKING_PATH_TOOL: Tab.IMPROVEMENTS,
	TerrainTypes.Type.FLOWER_BED: Tab.TERRAIN,
	"decoration": Tab.IMPROVEMENTS,
	"building": Tab.BUILDINGS,
	"vertex": Tab.ELEVATION,
	"flat": Tab.ELEVATION,
	"gradual": Tab.ELEVATION,
	"play_course": Tab.PLAYER,
	"tournaments": Tab.PLAYER,
	"world_map": Tab.CLUB,
	"course_map": Tab.CLUB,
	"holes_map": Tab.HOLES,
	"staff_map": Tab.STAFF,
	"aura_map": Tab.CLUB,
	"marketing": Tab.CLUB,
	"course_milestones": Tab.CLUB,
	"world_milestones": Tab.CLUB,
	"achievements": Tab.CLUB,
	"scorecard": Tab.HOLES,
	"review": Tab.CLUB,
	"finance": Tab.CLUB,
	"feed": Tab.CLUB,
}

## The tool hotkeys this shelf dispatches. InputBindings owns their keys and
## the Settings screen edits them; this list keeps main.gd from claiming a
## course-tool key it does not handle.
const TOOL_SHORTCUTS: Array[String] = [
	"terrain_fairway", "terrain_rough", "terrain_green", "terrain_tee",
	"terrain_bunker", "terrain_water", "terrain_out_of_bounds", "terrain_path",
	"terrain_firm_fairway", "terrain_waste_bunker", "terrain_deep_rough",
	"terrain_pot_bunker", "terrain_stream", "terrain_rocks", "terrain_brush",
	"terrain_small_boulders", "terrain_large_boulders", "terrain_flowers",
	"tool_trees", "tool_building", "tool_decoration", "tool_open_hole",
	"tool_bulldozer", "tab_terrain", "tab_improvements", "tab_elevation",
	"elevation_vertex", "elevation_flat", "elevation_gradual",
]

const TOOL_ROW_HEIGHT := 30
const COURSE_TILE_COLUMNS := 8  # Top row runs tee -> out of bounds, bottom row fairway -> large boulders
const TILE_ROWS := 2  # Course and building tiles always sit in two interlocking rows
## Tiles that lead the Improvements honeycomb ahead of the decoration
## catalogue — just the walking path, which opens the top row. The shelf's
## width counts it, so adding the path keeps the two rows balanced.
const IMPROVEMENTS_LEAD_TILES := 1
## Vertical rhythm of the tile rows: two rows of TerrainTileButton.BUTTON_SIZE
## tiles span 1.5 tiles, plus the gap where the lower row tucks into the
## notches of the row above, plus the breathing room kept above the first row
## and below the last — together filling the toolbar page height without the
## rows touching each other or the edges of the page.
const TILE_H_SEPARATION := 8
const TILE_V_SEPARATION := 20
const TILE_V_PADDING := 20
## The Elevation tab's three Square Selectors share one honeycomb of a single
## row — Vertex, Flat Square, Gradual Square.
const ELEVATION_SELECTOR_COLUMNS := 3
## Half the course tabs' vertical padding: the selector diamonds are twice as
## tall, so their single row fills the same page height as the two interlocking
## course rows and the toolbar never changes height with the tab.
const ELEVATION_V_PADDING := 15
## Paint-brush sizes in tiles. Same 1×1 through 9×9 steps as the Elevation Brush.
const BRUSH_SIZES: Array[int] = [1, 2, 3, 4, 5, 6, 7, 8, 9]

## What the Terrain and Elevation Brush Size plates read: the size in tiles on
## its own ("1", "5", "9"), not a "1x1" width-by-height pair. Square brushes
## are always the same across and down, so the second number only repeated the
## first.
static func brush_size_text(tiles: int) -> String:
	return str(tiles)

## The brush controls' cells: the header row's shape toggle, size chip and step
## buttons match the Inspect button's diameter, with a small gap between them.
const BRUSH_DOCK_CELL := InspectButton.BUTTON_DIAMETER
const BRUSH_DOCK_GAP := 2.0
## Holes stack three deep per column and the columns run off to the right, so
## the tab grows along the axis the page already scrolls on and never past the
## bottom bar's height.
const HOLE_COLUMN_HEIGHT := 3
## Golfers on the course stack three deep per column, for the same reason: the
## columns run off to the right where the page scrolls, so a busy course grows
## sideways instead of downwards past the bottom bar's height.
const GOLFER_COLUMN_HEIGHT := 3
const GOLFER_COLUMN_GAP := 10  # Between two columns of golfers
const GOLFER_ROW_GAP := 4  # Between two golfers in the same column
const OPEN_HOLE_TOOLTIP := "Pair the waiting tee box with the waiting green with a hole"
const OPEN_HOLE_BLOCKED_TOOLTIP := "Needs exactly one unused tee box and one unused green with a hole"
## What the Bulldozer removes — improvements and buildings only. Course
## Terrain tiles are ground paint: repaint them with another tile instead.
const BULLDOZER_TOOLTIP := "Demolish decorations, walking paths and buildings. Click or drag over them. Fees: $5 per path tile, $20 per decoration or building. Course Terrain tiles are not affected — any Course Terrain tile replaces any other, including trees."
## The Build tabs whose tiles the Inspect mode reads: every shelf in the Build
## section pins one Inspect toggle, so it is beside terrain, improvements,
## buildings and elevation work alike. Manage and Golfers pin none.
const INSPECT_TABS := [Tab.TERRAIN, Tab.IMPROVEMENTS, Tab.BUILDINGS, Tab.ELEVATION]

var hole_grid: GridContainer = null  # Course holes buttons, three to a column (filled by main.gd)
var terrain_grid: TerrainGrid = null  # Course terrain grid, for checking orphaned tee/green tiles
var _hole_register: HBoxContainer = null
var _hole_detail: HBoxContainer = null
var _hole_scorecard: CourseScorecardView = null  # Shown in place of the register
var _scorecard_open := false
var _selected_hole: int = 0
var golfer_data_provider: Callable = Callable()  # -> Array of golfer row dicts

var _current_tool: int = -1
var _tool_buttons: Dictionary = {}  # tool_type -> ToolButton
var current_tab: int = Tab.TERRAIN
var current_section: int = Section.BUILD
## True while the player has hidden the open section with its section button.
var section_collapsed: bool = false
var _last_tabs := {Section.BUILD: Tab.TERRAIN, Section.MANAGE: Tab.CLUB, Section.GOLFERS: Tab.GOLFERS}
var _tab_buttons: Dictionary = {}
var _tab_rail: Control
var _page_title: Label
var _pages: Array[Control] = []  # One wrapper per tab; the scroll + fixed chrome
## The container the pages sit in, inside the curved window. The window carries
## their combined minimum height, which the old body column used to.
var _pages_container: PanelContainer = null
## The shelf's fairway backdrop (see ShelfFanBackdrop): painted behind the tab
## rail and the page title so the right shelf reads as the bottom-left fan's
## neighbour on one continuous mown fairway. It is this control's first child,
## so every circle and tile the toolbar adds later lands on top of it.
var _backdrop: ShelfFanBackdrop = null
## The curved window the pages are cut to (see ShelfPageWindow): it paints the
## shelf's inner silhouette and clips every page to it, so a page scrolls under
## the curved tab buttons instead of stopping at a straight edge beside them.
var _page_window: ShelfPageWindow = null
var _sync_pending := false  # True when the fairway needs re-syncing after layout
# The row of tool buttons in the top-right of the shelf header. It holds the
# Inspect toggle, the brush size stepper group, the brush shape toggle and the
# Bulldozer button — the controls that used to be pinned to each page's
# corners. The row floats over the empty top-right of the page area, beside
# the page title at the top-left, and stays in step with the rail's width.
var _header_row: Control = null
var _inspect_button: InspectButton = null  # The shared Inspect toggle
var _bulldozer_button: BulldozerButton = null  # The shared Bulldozer button
var _header_terrain_shape: BrushShapeButton = null  # Terrain brush shape in the header row
var _header_terrain_size: HBoxContainer = null  # Terrain brush size stepper in the header row
var _header_elevation_shape: BrushShapeButton = null  # Elevation brush shape in the header row
var _header_elevation_size: HBoxContainer = null  # Elevation brush size stepper in the header row
var _brush_size: int = 1
var _round_brush := true
var _brush_limit: int = HoleLayout.UNLIMITED_BRUSH  # 1 = current tool paints a single tile
var _brush_labels: Array[Label] = []
var _brush_buttons: Array[Button] = []
var _brush_shape_buttons: Array[Button] = []
# Elevation brush: the Square Selector tools share one size and shape,
# separate from the terrain paint brush above. Switching between Flat and
# Gradual keeps the same settings, and the controls stay usable even when
# neither Square tool is selected. The controls live in the shelf header's tool
# row (see _build_header_row).
var _elevation_tool: String = ""  # "vertex" | "flat" | "gradual" | "" (none)
var _elevation_size: int = 3
var _elevation_square := true
var _elevation_brush_labels: Array[Label] = []
var _elevation_brush_buttons: Array[Button] = []
var _elevation_brush_shape_buttons: Array[Button] = []
var _open_hole_buttons: Array[ToolButton] = []
var _green_tile_button: TerrainTileButton = null
var _tee_tile_button: TerrainTileButton = null
var _green_places_cup := true
var _tee_box_can_place: bool = true
var _tee_box_blocker: String = ""
var _visitor_shelf: HBoxContainer = null  # Active golfers first, followed by past visitors
var _visitor_archive: Dictionary = {}
var _visitor_register: HBoxContainer
var _visitor_detail: HBoxContainer
var _selected_visitor := ""
var player_tab: PlayerTab
var _building_registry: Dictionary = {}
var _building_shelf: TileHoneycomb = null
var _decoration_registry: Dictionary = {}
var _decoration_shelf: TileHoneycomb = null
var _decoration_tiles: Dictionary = {}  # decoration type -> DecorationTileButton
var _path_tile: TerrainTileButton = null  # Walking path tile leading the shelf
var _course_tiles: TileHoneycomb = null
var _elevation_selectors: TileHoneycomb = null  # Vertex / Flat Square / Gradual Square
var _landscape_buttons: Array[Node] = []
## The Club tab's Feed card and how many events it is holding unread. The
## card moved here from the bottom-left control stack; the count is kept so
## the Club tab button (and, through feed_unread_count_changed, the Manage
## section button) can carry the same badge while the card is off screen.
var feed_button: DockActionButton = null
var feed_unread_count: int = 0
var _selected_string_tool: String = ""
var _refresh_timer: Timer = null
var _staff_panel: StaffPanel = null

func _ready() -> void:
	_build_ui()
	EventBus.theme_changed.connect(_on_theme_changed)
	EventBus.hole_updated.connect(_on_hole_event_updated)
	EventBus.hole_toggled.connect(_on_hole_event_toggled)
	EventBus.hole_deleted.connect(_on_hole_event_deleted)
	EventBus.holes_reordered.connect(_on_holes_event_reordered)
	EventBus.hole_difficulty_changed.connect(_on_hole_event_difficulty_changed)
	EventBus.golfer_finished_hole.connect(_on_golfer_finished_hole_event)
	EventBus.hole_created.connect(_on_hole_event_created)
	EventBus.record_broken.connect(_on_record_broken_event)
	EventBus.new_game_started.connect(_on_new_game_reset_holes_tab)
	EventBus.load_completed.connect(_on_load_completed_reset_holes_tab)
	if has_node("/root/Screen") and not Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.connect(_on_screen_changed)
	# The fairway's hub and sockets follow the rail whenever the shelf is
	# laid out or resized, not just when the screen class changes. The rail's
	# circles only settle once the first layout has run, so the sync is
	# deferred to the next process frame.
	resized.connect(_on_resized)
	apply_screen()
	_sync_pending = true

func _exit_tree() -> void:
	if EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.disconnect(_on_theme_changed)
	if EventBus.hole_updated.is_connected(_on_hole_event_updated):
		EventBus.hole_updated.disconnect(_on_hole_event_updated)
	if EventBus.hole_toggled.is_connected(_on_hole_event_toggled):
		EventBus.hole_toggled.disconnect(_on_hole_event_toggled)
	if EventBus.hole_deleted.is_connected(_on_hole_event_deleted):
		EventBus.hole_deleted.disconnect(_on_hole_event_deleted)
	if EventBus.holes_reordered.is_connected(_on_holes_event_reordered):
		EventBus.holes_reordered.disconnect(_on_holes_event_reordered)
	if EventBus.hole_difficulty_changed.is_connected(_on_hole_event_difficulty_changed):
		EventBus.hole_difficulty_changed.disconnect(_on_hole_event_difficulty_changed)
	if EventBus.golfer_finished_hole.is_connected(_on_golfer_finished_hole_event):
		EventBus.golfer_finished_hole.disconnect(_on_golfer_finished_hole_event)
	if EventBus.hole_created.is_connected(_on_hole_event_created):
		EventBus.hole_created.disconnect(_on_hole_event_created)
	if EventBus.record_broken.is_connected(_on_record_broken_event):
		EventBus.record_broken.disconnect(_on_record_broken_event)
	if EventBus.new_game_started.is_connected(_on_new_game_reset_holes_tab):
		EventBus.new_game_started.disconnect(_on_new_game_reset_holes_tab)
	if EventBus.load_completed.is_connected(_on_load_completed_reset_holes_tab):
		EventBus.load_completed.disconnect(_on_load_completed_reset_holes_tab)
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)

## Fit the curved rail into the available width without pushing the shelf or
## the fixed page controls off a phone-sized screen. The page still scrolls.
func apply_screen() -> void:
	if _tab_rail == null:
		return
	var available := Screen.window_size.x
	var parent := get_parent() as HBoxContainer
	if parent:
		# The bottom bar has the fixed left dock alongside this shelf. Use the
		# window width too: on a live shrink the container may not have sorted yet.
		if parent.size.x > 0.0:
			available = minf(available, parent.size.x)
		for sibling in parent.get_children():
			if sibling != self and sibling is Control and sibling.visible:
				available -= sibling.get_combined_minimum_size().x
				available -= parent.get_theme_constant("separation")
	var rail_width := clampf(available - 2.0 * SHELF_PAD_X - SHELF_ROW_GAP
			- SHELF_BODY_MIN_WIDTH, TAB_RAIL_MIN_WIDTH, TAB_RAIL_WIDTH)
	var diameter := 52.0 if Screen.uses_touch_layout() else 44.0
	# Reserve enough height for all four tabs, even on a three-tab section.
	_tab_rail.custom_minimum_size = Vector2(rail_width, 4.0 * diameter + 3.0 * TAB_RAIL_GAP)
	custom_minimum_size.x = rail_width + 2.0 * SHELF_PAD_X + SHELF_ROW_GAP + SHELF_BODY_MIN_WIDTH
	for button in _tab_buttons.values():
		if not is_instance_valid(button):
			continue
		button.diameter = diameter
		button.custom_minimum_size = Vector2.ONE * diameter
		button.size = Vector2.ONE * diameter
		button.queue_redraw()
	_sync_pending = true

func _on_screen_changed(_size: Vector2, _world_scale: float) -> void:
	apply_screen()

## The left fan's theoretical ellipse extends slightly past its canvas. Mirror
## the visible portion, scaled to this rail, so the two coloured rims meet at
## the dock/shelf seam instead of ending at different heights.
static func _shelf_seam_inset(width: float, touch_layout: bool) -> float:
	var dock_radius := 0.0
	for i in BottomControlDock.SECTION_POSITIONS.size():
		dock_radius = maxf(dock_radius, BottomControlDock.SECTION_POSITIONS[i].x
				+ BottomControlDock.SECTION_SIZES[i])
	dock_radius += DockArcBackdrop.RIM_SIDE_MARGIN
	var dock_width := BottomControlDock.TOUCH_WIDTH if touch_layout else BottomControlDock.WIDTH
	return width * maxf(0.0, (dock_radius - dock_width) / dock_radius)

## Seat the visible tabs on the same mirrored ellipse as the backdrop. A plain
## Control lets them move horizontally instead of forcing a vertical column.
func _layout_tab_rail() -> void:
	var rail_rect := _tab_rail.get_global_rect()
	var rail_origin := rail_rect.position - get_global_position()
	var curve_width := rail_origin.x + rail_rect.size.x
	var inset := _shelf_seam_inset(curve_width, Screen.uses_touch_layout())
	var tabs: Array = SECTION_TABS[current_section]
	var count := tabs.size()
	if count == 0:
		return
	for i in count:
		var button: PixelCircleButton = _tab_buttons[tabs[i]]
		var diameter := button.diameter
		var radius := diameter * 0.5
		var t := float(i) / float(maxi(count - 1, 1))
		var center_y := rail_origin.y + radius + (rail_rect.size.y - diameter) * t
		var rim_x := ShelfFanBackdrop.rim_x_at(center_y, size, curve_width, inset)
		# Circles straddle the rim like the dock's, without leaving the rail or
		# stealing room from the page. Their native circular hit areas stay intact.
		var center_x := clampf(rim_x + radius * 0.85,
				rail_origin.x + radius, rail_origin.x + rail_rect.size.x - radius)
		button.position = Vector2(roundf(center_x - rail_origin.x - radius),
				roundf(center_y - rail_origin.y - radius))
		button.size = Vector2.ONE * diameter

## Hand the backdrop the current rail, tabs and title in shelf coordinates.
## Layout runs first so its sockets and rim always follow the visible buttons.
func _sync_backdrop() -> void:
	if _backdrop == null or _tab_rail == null:
		return
	_layout_tab_rail()
	var origin := get_global_position()
	# Seat the header row at the top-right of the shelf, like the page title
	# at the top-left. Its width is whatever its visible children need; it
	# hugs the right padding and sits at the top padding. On a shelf too
	# narrow for the row, hide it: the row would otherwise cover the tab rail
	# and swallow touches meant for the curved cutout.
	if _header_row != null:
		var visible_children := []
		for child in _header_row.get_children():
			if child.visible:
				visible_children.append(child)
		if visible_children.is_empty():
			_header_row.visible = false
		else:
			var row_width := 0.0
			for child in visible_children:
				row_width += child.get_combined_minimum_size().x
			if visible_children.size() > 1:
				row_width += float(_header_row.get_theme_constant("separation")) * float(visible_children.size() - 1)
			_header_row.visible = row_width <= size.x - 2.0 * SHELF_PAD_X
			if _header_row.visible:
				var row_size := Vector2(row_width, _header_row.get_combined_minimum_size().y)
				_header_row.global_position = Vector2(
					origin.x + size.x - SHELF_PAD_X - row_width,
					origin.y + HEADER_ROW_TOP_OFFSET)
				_header_row.size = row_size
	# Keep the page heading clear of the curved tab row: start it just after
	# the first tab medallion at the top of the rail, so the heading names the
	# page from the left of the shelf instead of at the rail's far end.
	var tabs: Array = SECTION_TABS[current_section]
	if tabs.size() > 0:
		var button: PixelCircleButton = _tab_buttons.get(tabs[0])
		if button != null:
			var title_left := button.get_global_rect().end.x - origin.x + SHELF_ROW_GAP + 30.0
			_page_title.position = Vector2(title_left, SHELF_PAD_Y)
			var title_width := size.x - title_left - SHELF_PAD_X
			# Keep the heading clear of the header row's buttons on the right:
			# the title truncates with an ellipsis before it reaches them.
			if _header_row != null and _header_row.visible:
				var row_left := _header_row.position.x
				title_width = maxf(row_left - title_left - SHELF_ROW_GAP, 0.0)
			_page_title.size = Vector2(title_width, HEADER_HEIGHT)
	var rail_rect := _tab_rail.get_global_rect()
	var curve_width := rail_rect.end.x - origin.x
	var inset := _shelf_seam_inset(curve_width, Screen.uses_touch_layout())
	_backdrop.set_curve(curve_width, inset)
	# The pages are cut to the same curve, so a page reaches under the tab rail
	# exactly as far as the fairway does and never over its rim.
	_page_window.set_curve(curve_width, inset)
	var viewport := get_viewport()
	var hub := Vector2(0.0, viewport.get_visible_rect().size.y) - origin
	var circles: Array = []
	for tab in SECTION_TABS[current_section]:
		var button: PixelCircleButton = _tab_buttons[tab]
		var rect := button.get_global_rect()
		var local := rect.position - origin
		circles.append(Vector3(local.x + rect.size.x * 0.5,
				local.y + rect.size.y * 0.5, rect.size.x * 0.5))
	_backdrop.set_hub(hub)
	_backdrop.set_circles(circles)
	if _page_title != null and _page_title.visible:
		var title_global := _page_title.get_global_rect()
		_backdrop.set_title_rule(Rect2(title_global.position - origin, title_global.size))
	else:
		_backdrop.set_title_rule(Rect2())

## Only the painted fairway consumes otherwise empty shelf clicks. Its children
## (including the parts of the circular tabs outside the rim) remain clickable.
func _has_point(point: Vector2) -> bool:
	if _backdrop == null:
		return Rect2(Vector2.ZERO, size).has_point(point)
	return ShelfFanBackdrop.contains_point(point, size, _backdrop.curve_width, _backdrop.seam_inset)

## TouchInput normally guards a control's whole rectangle against accidental
## painting. This shelf explicitly exposes its curved hit shape instead.
func has_touch_point(point: Vector2) -> bool:
	return _has_point(point)

func _on_resized() -> void:
	# The parent container can resize independently of the screen. Refit the
	# rail now, then sync the buttons once the container has sorted its children.
	apply_screen()
	_sync_pending = true

func _process(_delta: float) -> void:
	if _sync_pending:
		_sync_pending = false
		_sync_backdrop()

func _build_ui() -> void:
	# A rectangular PanelContainer frame would fill the transparent side of the
	# curve. The backdrop paints the entire shelf; an inset layout keeps text and
	# scrolling content clear of its rim instead.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	# The game theme gives every ScrollContainer a solid green panel. Clear it
	# locally for all shelf scrolls (including nested staff/player views), so
	# they reveal the translucent fairway instead of painting over it.
	theme = Theme.new()
	theme.set_stylebox("panel", "ScrollContainer", StyleBoxEmpty.new())
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_backdrop = ShelfFanBackdrop.new()
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_backdrop)
	# The pages ride in their own curved window, under the rail: it is added
	# after the fairway but before the rail, so the content is cut to the rim
	# and the tab medallions still sit on top of it.
	_page_window = ShelfPageWindow.new()
	_page_window.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_page_window)
	var margins := MarginContainer.new()
	margins.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margins.add_theme_constant_override("margin_left", int(SHELF_PAD_X))
	margins.add_theme_constant_override("margin_right", int(SHELF_PAD_X))
	margins.add_theme_constant_override("margin_top", int(SHELF_PAD_Y))
	margins.add_theme_constant_override("margin_bottom", int(SHELF_PAD_Y))
	add_child(margins)
	move_child(_backdrop, 0)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", int(SHELF_ROW_GAP))
	margins.add_child(row)
	_build_tab_rail(row)
	# The page heading rides over the top of the shelf and names the page for
	# the section that is open. It starts just after the first tab medallion
	# at the top of the rail (its position is synced in _sync_backdrop), so
	# the heading reads from the left of the page it names instead of sitting
	# at the far end of the tab rail. It takes no clicks: anything it covers
	# falls through to the page or the course beneath it.
	_page_title = Label.new()
	_page_title.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
	_page_title.add_theme_font_override("font", PixelCircleButton.FONT)
	_page_title.add_theme_font_size_override("font_size", 14)
	_page_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_page_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_page_title)
	_build_header_row()
	# The page shelf: the whole width between the shelf's side padding, from
	# under the heading to the bottom. Its left edge is the curved window above.
	var pages_container := PanelContainer.new()
	pages_container.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	pages_container.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	pages_container.offset_left = SHELF_PAD_X
	pages_container.offset_top = SHELF_PAD_Y + HEADER_HEIGHT
	pages_container.offset_right = -SHELF_PAD_X
	pages_container.offset_bottom = -SHELF_PAD_Y
	_page_window.add_child(pages_container)
	_pages_container = pages_container
	# The pages no longer grow a container of their own, so the window asks for
	# whatever height they need: the shelf never renders a page shorter than the
	# rows it holds.
	pages_container.minimum_size_changed.connect(_fit_page_window_height)
	for tab_index in TAB_TITLES.size():
		var page := _build_page(tab_index)
		page.visible = tab_index == Tab.TERRAIN
		pages_container.add_child(page)
		_pages.append(page)
	_fit_page_window_height()
	# The player already has a persistent set of pages. Hide its old text
	# navigation and move the skill-point badge onto the new circular rail.
	player_tab.use_external_navigation(_tab_buttons[Tab.PLAYER_SKILLS])
	player_tab.selection_changed.connect(_on_player_section_changed)
	select_tab(Tab.TERRAIN)
	_build_refresh_timer()

## Keep the shelf's minimum height honest. The pages ride in the curved window
## rather than in a container that grows with them, so the window carries their
## combined height plus the heading and the shelf's own padding.
func _fit_page_window_height() -> void:
	if _page_window == null or _pages_container == null:
		return
	_page_window.custom_minimum_size.y = SHELF_PAD_Y + HEADER_HEIGHT \
		+ _pages_container.get_combined_minimum_size().y + SHELF_PAD_Y

func _build_tab_rail(parent: HBoxContainer) -> void:
	_tab_rail = Control.new()
	_tab_rail.name = "SectionTabs"
	_tab_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tab_rail.custom_minimum_size = Vector2(TAB_RAIL_MIN_WIDTH, 0.0)
	parent.add_child(_tab_rail)
	for section in SECTION_TABS:
		for tab_index in SECTION_TABS[section]:
			var button := PixelCircleButton.new()
			button.name = "Tab%d" % tab_index
			button.glyph = TAB_ICONS[tab_index]
			button.accent = SECTION_COLORS[section]
			button.toggle_mode = true
			button.tooltip_text = TAB_TITLES[tab_index]
			button.accessibility_name = TAB_TITLES[tab_index]
			button.pressed.connect(select_tab.bind(tab_index))
			_tab_rail.add_child(button)
			_tab_buttons[tab_index] = button

func select_section(section: int) -> void:
	if SECTION_TABS.has(section):
		select_tab(_last_tabs[section])

## Section button handler: pressing the button of the section that is already
## open hides it; pressing any other section button (or a collapsed one) opens it.
func toggle_section(section: int) -> void:
	if not SECTION_TABS.has(section):
		return
	if section == current_section and not section_collapsed:
		collapse_section()
	else:
		select_section(section)

## Hide the section's tabs and tools. Hotkeys and tab selection bring it back.
func collapse_section() -> void:
	if section_collapsed:
		return
	section_collapsed = true
	visible = false
	section_visibility_changed.emit(false)

func expand_section() -> void:
	if not section_collapsed:
		return
	section_collapsed = false
	visible = true
	section_visibility_changed.emit(true)

func _sync_navigation(tab_index: int) -> void:
	for section in SECTION_TABS:
		if tab_index in SECTION_TABS[section]:
			current_section = section
			break
	_last_tabs[current_section] = tab_index
	for index in _tab_buttons:
		_tab_buttons[index].visible = index in SECTION_TABS[current_section]
		_tab_buttons[index].active = index == tab_index
		_tab_buttons[index].set_pressed_no_signal(index == tab_index)
	_page_title.text = "%s  /  %s" % [SECTION_TITLES[current_section].to_upper(), TAB_TITLES[tab_index]]
	_page_title.add_theme_color_override("font_color", SECTION_COLORS[current_section])
	# The shelf's fairway wears the open section's colour on its accent
	# details, the way the dock's fan trims its rim, and re-lays its sockets
	# for whichever medallions the section shows.
	if _backdrop:
		_backdrop.accent = SECTION_COLORS[current_section]
	_sync_pending = true
	section_changed.emit(current_section)

func _on_player_section_changed(index: int) -> void:
	# Round setup can select Play Course directly. Reflect that in the rail
	# only when the player view is already open; don't hijack a build action.
	if current_tab in PLAYER_TABS and current_tab != PLAYER_TABS[index]:
		select_tab(PLAYER_TABS[index])

func _build_page(tab_index: int) -> Control:
	# Each page is a plain wrapper Control holding the horizontally-scrollable
	# content. The tool buttons live in the shared header row at the top of the
	# shelf, not pinned to any page.
	var page = Control.new()
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var scroll = ScrollContainer.new()
	scroll.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.gui_input.connect(_on_scroll_gui_input.bind(scroll))
	# A plain Control does not inherit its children's minimum size, so keep the
	# page at least as tall as its scrolling shelf — the same height contract
	# the scroll-only pages used to hand the toolbar.
	scroll.minimum_size_changed.connect(
		func() -> void: page.custom_minimum_size = scroll.get_combined_minimum_size())
	page.add_child(scroll)
	page.custom_minimum_size = scroll.get_combined_minimum_size()

	var h_bar = scroll.get_h_scroll_bar()
	if h_bar:
		h_bar.custom_minimum_size = Vector2(0, 4)

	var hbox = HBoxContainer.new()
	hbox.add_theme_constant_override("separation", 8)
	hbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.alignment = BoxContainer.ALIGNMENT_BEGIN
	scroll.add_child(hbox)

	# Leading space before the first object, so the first tile/card never
	# rubs against the curved rim at the shelf's left edge.
	var lead := Control.new()
	lead.mouse_filter = Control.MOUSE_FILTER_IGNORE
	lead.custom_minimum_size.x = SHELF_CONTENT_LEAD
	hbox.add_child(lead)

	match tab_index:
		Tab.TERRAIN:
			_build_terrain_tab(hbox)
		Tab.IMPROVEMENTS:
			_build_improvements_tab(hbox)
		Tab.BUILDINGS:
			_build_buildings_tab(hbox)
		Tab.ELEVATION:
			_build_elevation_tab(hbox)
		Tab.HOLES:
			_build_holes_tab(hbox)
		Tab.GOLFERS:
			_build_golfers_tab(hbox)
		Tab.PLAYER:
			_build_player_tab(hbox)
		Tab.CLUB:
			_build_club_tab(hbox)
		Tab.STAFF:
			_build_staff_tab(hbox)

	return page

## The row of tool buttons in the top-right of the shelf header. Each build
## shelf shows its own controls: Terrain carries the Terrain Brush Shape and
## Brush Size buttons plus Inspect; Improvements and Buildings carry the
## Bulldozer and Inspect; Elevation carries its own Brush Shape and Brush Size
## buttons plus Inspect. Other shelves carry nothing. The row floats over the
## empty top-right of the page area, beside the page title at the top-left.
func _build_header_row() -> void:
	# A plain Control wrapper, like the page title: it is positioned in
	# _sync_backdrop, not by the parent's layout. The HBoxContainer inside it
	# lays the buttons out in a row and fills the wrapper.
	var wrapper := HBoxContainer.new()
	wrapper.name = "HeaderControls"
	wrapper.mouse_filter = Control.MOUSE_FILTER_IGNORE
	wrapper.add_theme_constant_override("separation", 8)
	# The PanelContainer's layout would expand and reposition this row on every
	# frame, overriding the manual positioning in _sync_backdrop. Making it a
	# top-level node keeps the layout from touching it; its global position is
	# set from the shelf's own global position in _sync_backdrop.
	wrapper.set_as_top_level(true)
	add_child(wrapper)
	_header_row = wrapper

	# Terrain brush shape: round/square toggle.
	_header_terrain_shape = _create_brush_shape(Vector2(BRUSH_DOCK_CELL, BRUSH_DOCK_CELL))
	_style_dock_cell(_header_terrain_shape)
	wrapper.add_child(_header_terrain_shape)

	# Terrain brush size: a small stepper group (-, NxN, +).
	_header_terrain_size = _create_brush_size_stepper(
		_on_brush_decrease, _on_brush_increase)
	wrapper.add_child(_header_terrain_size)

	# Bulldozer.
	_bulldozer_button = BulldozerButton.new()
	_bulldozer_button.name = "BulldozerButton"
	_bulldozer_button.accessibility_name = "Bulldozer"
	_bulldozer_button.accessibility_description = BULLDOZER_TOOLTIP
	_bulldozer_button.tooltip_text = BULLDOZER_TOOLTIP
	_bulldozer_button.pressed.connect(_on_tool_button_pressed.bind("bulldozer"))
	wrapper.add_child(_bulldozer_button)

	# Elevation brush shape: round/square toggle.
	_header_elevation_shape = _create_elevation_brush_shape_button()
	_style_dock_cell(_header_elevation_shape)
	wrapper.add_child(_header_elevation_shape)

	# Elevation brush size: a small stepper group (-, NxN, +).
	_header_elevation_size = _create_elevation_brush_size_stepper()
	wrapper.add_child(_header_elevation_size)

	# Inspect toggle (shared across all build shelves).
	var inspect := InspectButton.new()
	inspect.name = "InspectButton"
	inspect.toggled.connect(_on_inspect_button_toggled)
	wrapper.add_child(inspect)
	_inspect_button = inspect

	_update_elevation_brush_group()
	_sync_header_row_content()

## Show the controls the current shelf needs and hide the rest. Terrain shows
## the terrain brush shape and size stepper; Improvements and Buildings show
## the Bulldozer; Elevation shows its own brush shape and size stepper. Every
## build shelf shows Inspect; other shelves show nothing.
func _sync_header_row_content() -> void:
	if _header_row == null:
		return
	var tab := current_tab
	var is_build := tab in SECTION_TABS[Section.BUILD]
	_header_terrain_shape.visible = tab == Tab.TERRAIN
	_header_terrain_size.visible = tab == Tab.TERRAIN
	_bulldozer_button.visible = tab in [Tab.IMPROVEMENTS, Tab.BUILDINGS]
	_header_elevation_shape.visible = tab == Tab.ELEVATION
	_header_elevation_size.visible = tab == Tab.ELEVATION
	_inspect_button.visible = is_build

func _on_inspect_button_toggled(enabled: bool) -> void:
	inspect_toggled.emit(enabled)

## The shared Inspect toggle. Kept as a stable reference for code that just
## needs one button to drive the mode.
func inspect_button() -> InspectButton:
	return _inspect_button

## Press (or release) the Inspect toggle without re-emitting `toggled`, so the
## button stays in step with the mode no matter where the mode was cancelled
## (Esc, right-click, another tool).
func set_inspect_active(active: bool) -> void:
	if is_instance_valid(_inspect_button):
		_inspect_button.set_pressed_no_signal(active)
		_inspect_button.active = active
		_inspect_button.queue_redraw()

## True while the Inspect toggle shows Inspect mode as active.
func is_inspect_active() -> bool:
	return is_instance_valid(_inspect_button) and _inspect_button.button_pressed

## Show on the Bulldozer button whether bulldozer mode is running.
func set_bulldozer_active(active: bool) -> void:
	if is_instance_valid(_bulldozer_button):
		_bulldozer_button.set_active(active)

## The horizontally-scrollable shelf of a tab page (the wrapper's full-rect child).
func page_scroll(tab_index: int) -> ScrollContainer:
	return _pages[tab_index].get_child(0) as ScrollContainer

## The content row a tab builder laid its groups into.
func page_content(tab_index: int) -> HBoxContainer:
	return page_scroll(tab_index).get_child(0) as HBoxContainer

func _on_scroll_gui_input(event: InputEvent, scroll: ScrollContainer) -> void:
	if event is InputEventMouseButton and event.pressed:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP:
			scroll.scroll_horizontal = maxi(0, scroll.scroll_horizontal - 50)
			scroll.accept_event()
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN:
			scroll.scroll_horizontal += 50
			scroll.accept_event()

# =============================================================================
# Tab Builders (Horizontal Layouts)
# =============================================================================

func _build_terrain_tab(hbox: HBoxContainer) -> void:
	# The tab is nothing but the tile honeycomb: the brush controls it paints
	# with live in the shelf header's tool row (see _build_header_row) so they
	# stay above the tiles instead of scrolling off with them. (Demolition
	# is not a course tool: the Bulldozer button sits in the header row too,
	# but only removes Improvements and Buildings tiles. Open Hole is not a
	# paint tool either — it nestles between the tee and green tiles it pairs,
	# see _add_open_hole_notch.)

	# The course tiles share one honeycomb of two rows, the bottom row shifted
	# half a tile right so each diamond drops into a notch between the two tiles
	# above it. Top row: Tee Box, Green, Bunker, Rough, Pot Bunker, Stream,
	# Water, Out of Bounds. Bottom row: Fairway, Firm Fairway, Deep Rough,
	# Waste Bunker, Brush, Rocks, Small Boulders, Large Boulders.
	var tiles_grid = TileHoneycomb.new()
	_course_tiles = tiles_grid
	tiles_grid.name = "CourseTilesGrid"
	tiles_grid.columns = COURSE_TILE_COLUMNS
	tiles_grid.tile_size = TerrainTileButton.BUTTON_SIZE
	tiles_grid.h_separation = TILE_H_SEPARATION
	tiles_grid.v_separation = TILE_V_SEPARATION
	tiles_grid.v_padding = TILE_V_PADDING
	tiles_grid.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	# Top row: the tee and the green first, then the hazards and trouble.
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.TEE_BOX, "name": "Tee Box", "hotkey": "4", "desc": "Tee for one hole — a single tile (1x1). Only one tee box may wait on the course at a time", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.GREEN, "name": "Green", "hotkey": "3", "desc": "Next green placement is a Green With Hole (one tile with a cup). The flag on this tile shows when it will place a cup.", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.BUNKER, "name": "Bunker", "hotkey": "5", "desc": "Shallow sand-trap hazard", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.ROUGH, "name": "Rough", "hotkey": "2", "desc": "Longer grass bordering fairways", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.POT_BUNKER, "name": "Pot Bunker", "hotkey": "Shift+5", "desc": "Small, deep bunker with a steep stacked-turf face. Wedge only, and the ball barely advances", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.STREAM, "name": "Stream", "hotkey": "Shift+6", "desc": "Running water hazard with a one-stroke penalty. Paint it in lines; golfers can still walk across", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.WATER, "name": "Water", "hotkey": "6", "desc": "Water hazard with penalty", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.OUT_OF_BOUNDS, "name": "Out of Bounds", "hotkey": "7", "desc": "Boundary area with stroke penalty", "tile_preview": true})
	# Bottom row: playing surfaces and natural ground, each variant beside its parent.
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.FAIRWAY, "name": "Fairway", "hotkey": "1", "desc": "Mowed playing surface for approach shots", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.FIRM_FAIRWAY, "name": "Firm Fairway", "hotkey": "9", "desc": "Fast-running links turf: a tight lie, and balls bound on and roll about 60% farther", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.DEEP_ROUGH, "name": "Deep Rough", "hotkey": "Shift+2", "desc": "Knee-high grass that grabs rolling balls. Shots from it lose accuracy and 40% of their distance", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.WASTE_BUNKER, "name": "Waste Bunker", "hotkey": "0", "desc": "Natural sandy scrubland. Not a hazard: plays like sandy rough and needs no upkeep", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.BRUSH, "name": "Brush", "hotkey": "Shift+8", "desc": "Dense scrub that swallows the ball. Only a wedge hacks it out", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.ROCKS, "name": "Rocks", "hotkey": "Shift+7", "desc": "Stony ground scattered with stones: the worst lie on the course, wedge only", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.SMALL_BOULDERS, "name": "Small Boulders", "hotkey": "Shift+9", "desc": "Stony ground paved with small boulders: the worst lie on the course, wedge only", "tile_preview": true})
	_add_tool_button(tiles_grid, {"type": TerrainTypes.Type.LARGE_BOULDERS, "name": "Large Boulders", "hotkey": "Shift+0", "desc": "Stony ground broken up by large boulders: the worst lie on the course, wedge only", "tile_preview": true})
	# The grid carries its own breathing room above and below the rows, so it
	# keeps that spacing instead of stretching to fill the whole page height.
	hbox.add_child(_make_tab_group("", tiles_grid, true))

	_populate_landscape_tiles()

	# Open Hole pairs the tee box and the green, which share the top row's first
	# two slots: nestle the action into the notch between them. Added after the
	# catalogue tiles so the honeycomb's tile flow (course tiles first, tree
	# tiles behind them) is exactly as it was — a nestled child takes no slot.
	_add_open_hole_notch(tiles_grid, 0)

## The Open Hole action as a half-size course cell nestled into the notch
## between the tab's Tee Box and Green tiles — the pair it opens. `left_slot` is
## the flow slot of the tile to the left of the notch, so slot 0 puts it between
## the tee box and the green.
func _add_open_hole_notch(tiles_grid: TileHoneycomb, left_slot: int) -> OpenHoleNotchButton:
	var open_hole_btn := OpenHoleNotchButton.new()
	open_hole_btn.name = "OpenHoleButton"
	open_hole_btn.configure("open_hole", "Open Hole", "[H]", "H", OPEN_HOLE_TOOLTIP)
	open_hole_btn.tool_pressed.connect(_on_tool_button_pressed)
	tiles_grid.set_notch_child(open_hole_btn, left_slot)
	_open_hole_buttons.append(open_hole_btn)
	_tool_buttons["open_hole"] = open_hole_btn
	return open_hole_btn

func _build_improvements_tab(hbox: HBoxContainer) -> void:
	# Every improvement — the walking path and each ornament in The Garden Shed —
	# sits in one honeycomb of the same interlocking isometric tiles used by
	# Course Terrain and Buildings: two rows, no heading (the tiles carry their
	# own captions), and a rich hover tooltip per tile. The path leads the top
	# row because it is the improvement players reach for while they shape the
	# course, so it opens the tab instead of standing beside it in its own box.
	# The page scrolls sideways when the catalogue is wider than the window.
	_decoration_shelf = TileHoneycomb.new()
	_decoration_shelf.name = "DecorationShelf"
	_decoration_shelf.tile_size = TerrainTileButton.BUTTON_SIZE
	_decoration_shelf.h_separation = TILE_H_SEPARATION
	_decoration_shelf.v_separation = TILE_V_SEPARATION
	_decoration_shelf.v_padding = TILE_V_PADDING
	_decoration_shelf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_decoration_shelf.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	_add_path_tile()
	_populate_decoration_shelf()
	hbox.add_child(_make_tab_group("", _decoration_shelf, true))

## The walking path drawn as a course tile and laid in the first slot of the
## Improvements honeycomb. It is a painting tool rather than a catalogue entry,
## so `_populate_decoration_shelf()` preserves it while it rebuilds the shelf.
func _add_path_tile() -> void:
	if is_instance_valid(_path_tile):
		return
	_path_tile = _add_tool_button(_decoration_shelf, {
		"type": TerrainTypes.WALKING_PATH_TOOL,
		"name": "Path",
		"hotkey": "8",
		"desc": "Thin dirt walking path laid over rough, deep rough, waste bunker, brush, rocks, boulders, streams, wild flowers and trees. Each tile is a dot; edge-adjacent dots join into one trail, and a trail that reaches the clubhouse is paved.",
		"tile_preview": true,
	}) as TerrainTileButton

func _on_theme_changed(_theme: int) -> void:
	_populate_landscape_tiles()
	# The Buildings tab's catalogue is location-dependent: Links courses trade
	# the Snack Bar for a Pub, Desert courses get the Spa, and so on.
	_populate_building_shelf()

func _populate_landscape_tiles() -> void:
	if not is_instance_valid(_course_tiles):
		return
	# Detach old landscape tiles immediately so repeated theme changes cannot
	# leave duplicate tiles in the layout or stale entries in the tool lookup.
	for key in _tool_buttons.keys():
		if _tool_buttons[key] in _landscape_buttons:
			_tool_buttons.erase(key)
	for child in _landscape_buttons:
		_course_tiles.remove_child(child)
		child.queue_free()
	_landscape_buttons.clear()

	var theme_id: int = CourseTheme.Type.PARKLAND
	if GameManager:
		theme_id = GameManager.current_theme
	var theme_trees: Array = CourseTheme.get_tree_types(theme_id)
	var total_tiles: int = 1 + theme_trees.size()
	_course_tiles.columns = COURSE_TILE_COLUMNS + ceili(float(total_tiles) / TILE_ROWS)

	# Wild Flowers terrain tile
	var fb_btn := _add_tool_button(_course_tiles, {
		"type": TerrainTypes.Type.FLOWER_BED,
		"name": "Wild Flowers",
		"hotkey": "Shift+F",
		"desc": "Colorful landscaping",
		"tile_preview": true
	})
	_tool_buttons[TerrainTypes.Type.FLOWER_BED] = fb_btn

	# Woodland: one ordinary paint tile per species the theme grows. They behave
	# like every other tile on the tab — cost, replacement and the Bulldozer all
	# read them from TerrainTypes — and only the canopy differs (TreeOverlay).
	for tree_type in theme_trees:
		var tree_btn := _add_tool_button(_course_tiles, {
			"type": tree_type,
			"name": TerrainTypes.get_type_name(tree_type),
			"desc": _tree_tile_description(tree_type),
			"tile_preview": true,
		})
		_landscape_buttons.append(tree_btn)

	# Extend both existing course rows, rather than starting another honeycomb.
	# Keeping the first COURSE_TILE_COLUMNS tiles in each row preserves the
	# course layout. A child nestled into a notch (the Open Hole button) is not
	# a tile, so it is not part of this flow and keeps its place between the tee
	# and the green.
	var tiles: Array[Control] = _course_tiles.flow_children()
	_landscape_buttons.assign(tiles.slice(COURSE_TILE_COLUMNS * TILE_ROWS))
	for i in _course_tiles.columns - COURSE_TILE_COLUMNS:
		_course_tiles.move_child(_landscape_buttons[i], COURSE_TILE_COLUMNS + i)
	_update_selection_highlight()

func _build_buildings_tab(hbox: HBoxContainer) -> void:
	# Optional facilities use the same interlocking isometric buttons as Course
	# & Hazards. Required buildings (currently the clubhouse) are supplied with
	# the course and aren't construction choices in this shelf.
	# Tiles are laid out in two rows (columns follow the catalogue size, see
	# _populate_building_shelf) and the page scrolls sideways when needed.
	_building_shelf = TileHoneycomb.new()
	_building_shelf.name = "BuildingShelf"
	_building_shelf.columns = tile_columns(_optional_building_types().size())
	_building_shelf.tile_size = TerrainTileButton.BUTTON_SIZE
	_building_shelf.h_separation = TILE_H_SEPARATION
	_building_shelf.v_separation = TILE_V_SEPARATION
	_building_shelf.v_padding = TILE_V_PADDING
	_building_shelf.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_building_shelf.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# No group heading or INFO blurb: the tiles speak for themselves and the
	# rich hover tooltip carries each facility's cost and upkeep.
	# The shelf carries its own breathing room above and below the rows, so it
	# keeps that spacing instead of stretching to fill the whole page height.
	hbox.add_child(_make_tab_group("", _building_shelf, true))
	_populate_building_shelf()

func set_building_registry(registry: Dictionary) -> void:
	_building_registry = registry.duplicate(true)
	_populate_building_shelf()

func _populate_building_shelf() -> void:
	if not is_instance_valid(_building_shelf):
		return
	for child in _building_shelf.get_children():
		_building_shelf.remove_child(child)
		child.queue_free()
	var building_types := _optional_building_types()
	_building_shelf.columns = tile_columns(building_types.size())
	for building_type in building_types:
		var data: Dictionary = _building_registry[building_type]
		var button := BuildingTileButton.new()
		button.configure_building(str(building_type), data)
		button.pressed.connect(_on_building_card_pressed.bind(str(building_type)))
		_building_shelf.add_child(button)

## The clubhouse (and any other required building) is created as part of the
## course, so required entries remain in the registry for game logic but don't
## appear as player-placeable choices. Buildings are also location-dependent:
## the catalogue only lists facilities the current course theme allows (see
## BuildingAvailability), so a Links course is offered a Pub instead of a
## Snack Bar, a Desert course a Spa, a Tropical course a Swim Club.
func _optional_building_types() -> Array:
	var building_types: Array = []
	var theme_id: int = CourseTheme.Type.PARKLAND
	if GameManager:
		theme_id = GameManager.current_theme
	for building_type in _building_registry:
		var data: Dictionary = _building_registry[building_type]
		if data.get("required", false):
			continue
		if not BuildingAvailability.is_available(data, theme_id):
			continue
		building_types.append(building_type)
	return building_types

## Columns needed to lay `count` catalogue tiles out in TILE_ROWS rows.
static func tile_columns(count: int) -> int:
	return maxi(1, ceili(float(count) / TILE_ROWS))

func _on_building_card_pressed(building_type: String) -> void:
	_reveal_tab_for_tool("building")
	building_selected.emit(building_type)

# =============================================================================
# Improvements shelf: the walking path tile plus the decoration catalogue
# =============================================================================

func set_decoration_registry(registry: Dictionary) -> void:
	_decoration_registry = registry.duplicate(true)
	_populate_decoration_shelf()

func _populate_decoration_shelf() -> void:
	if not is_instance_valid(_decoration_shelf):
		return
	for child in _decoration_shelf.get_children():
		if child == _path_tile:
			continue  # The path leads the shelf; it is not part of the catalogue.
		_decoration_shelf.remove_child(child)
		child.queue_free()
	_decoration_tiles.clear()
	_decoration_shelf.columns = tile_columns(_decoration_registry.size() + IMPROVEMENTS_LEAD_TILES)
	for dec_type in ordered_decoration_types():
		var data: Dictionary = _decoration_registry[dec_type]
		var button := DecorationTileButton.new()
		button.configure_decoration(str(dec_type), data)
		button.pressed.connect(_on_decoration_card_pressed.bind(str(dec_type)))
		_decoration_shelf.add_child(button)
		_decoration_tiles[str(dec_type)] = button
	if is_instance_valid(_path_tile):
		# Rebuilt rows append after the new catalogue tiles, so put the path back
		# in slot 0: the first tile of the top row of the honeycomb.
		_decoration_shelf.move_child(_path_tile, 0)
	refresh_decoration_unlocks()

## Decoration types in the order The Garden Shed listed them: one category
## after another, each keeping the catalogue's own order. Types with an
## unknown category trail the shelf in catalogue order.
func ordered_decoration_types() -> Array:
	var ordered: Array = []
	for category in DecorationTileButton.CATEGORY_ORDER:
		for dec_type in _decoration_registry:
			if str(_decoration_registry[dec_type].get("category", "")) == category:
				ordered.append(dec_type)
	for dec_type in _decoration_registry:
		if not ordered.has(dec_type):
			ordered.append(dec_type)
	return ordered

func _on_decoration_card_pressed(decoration_type: String) -> void:
	var button: DecorationTileButton = _decoration_tiles.get(decoration_type, null)
	if button and button.disabled:
		return  # Locked ornaments stay on the shelf but cannot be placed.
	_reveal_tab_for_tool("decoration")
	decoration_selected.emit(decoration_type)

## Re-check every ornament against the current rating, reputation and hole
## count: the shelf opens with what the course has unlocked so far.
func refresh_decoration_unlocks() -> void:
	for dec_type in _decoration_tiles:
		var button: DecorationTileButton = _decoration_tiles[dec_type]
		if not is_instance_valid(button):
			continue
		button.set_locked(not is_decoration_unlocked(button.decoration_data),
			decoration_unlock_text(button.decoration_data))

func is_decoration_unlocked(decoration_data: Dictionary) -> bool:
	if not GameManager:
		return true
	var unlock = decoration_data.get("unlock")
	if unlock == null or not unlock is Dictionary or unlock.is_empty():
		return true
	match str(unlock.get("type", "")):
		"star_rating":
			return GameManager.course_rating.get("stars", 0) >= int(unlock.get("value", 99))
		"reputation":
			return GameManager.reputation >= int(unlock.get("value", 999))
		"holes_built":
			var hole_count: int = GameManager.current_course.holes.size() if GameManager.current_course else 0
			return hole_count >= int(unlock.get("value", 99))
	return false

## Human-readable form of a decoration's unlock requirement ("" when it has none).
func decoration_unlock_text(decoration_data: Dictionary) -> String:
	var unlock = decoration_data.get("unlock")
	if unlock == null or not unlock is Dictionary or unlock.is_empty():
		return ""
	match str(unlock.get("type", "")):
		"star_rating":
			return "%d★ rating" % int(unlock.get("value", 0))
		"reputation":
			return "%d reputation" % int(unlock.get("value", 0))
		"holes_built":
			return "%d holes" % int(unlock.get("value", 0))
	return ""

func _build_elevation_tab(hbox: HBoxContainer) -> void:
	# The three Square Selectors share one honeycomb of interlocking diamonds —
	# Vertex, Flat Square and Gradual Square in a single row. The Elevation
	# Brush controls that belong to the two Square tools live in the shelf
	# header's tool row (see _build_header_row), so the tab itself is just the
	# three selector tiles.
	var selectors = TileHoneycomb.new()
	selectors.name = "ElevationSelectors"
	_elevation_selectors = selectors
	selectors.columns = ELEVATION_SELECTOR_COLUMNS
	selectors.tile_size = ElevationSelectorButton.SELECTOR_TILE_SIZE
	selectors.h_separation = TILE_H_SEPARATION
	selectors.v_separation = TILE_V_SEPARATION
	selectors.v_padding = ELEVATION_V_PADDING
	selectors.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_add_tool_button(selectors, {"type": "vertex", "elevation_preview": true, "name": "Vertex", "icon": "◆", "hotkey": "V", "desc": "Right click raises, left click lowers, a single grid vertex by one step"})
	_add_tool_button(selectors, {"type": "flat", "elevation_preview": true, "name": "Flat Square", "icon": "■", "hotkey": "+", "desc": "Right click: raise the square's lowest vertices one level. Left click: lower its highest ones one level. Even ground moves as one slab"})
	_add_tool_button(selectors, {"type": "gradual", "elevation_preview": true, "name": "Gradual Square", "icon": "▲", "hotkey": "-", "desc": "Right click raises, left click lowers, the middle of the square; nearby vertices keep at most one step of slope"})
	# The grid carries its own breathing room above and below the row, so it keeps
	# that spacing instead of stretching to fill the whole page height.
	hbox.add_child(_make_tab_group("", selectors, true))

func _build_holes_tab(hbox: HBoxContainer) -> void:
	# The Course Terrain tab owns the Open Hole action. When no hole is picked,
	# the tab shows the course holes register — the Holes Map card leading on
	# the left, then one button per hole, three to a column. Clicking a hole
	# button opens that hole's management actions and statistics in place of
	# the register, the same way clicking a visitor opens their profile on
	# Visiting Golfers.
	_hole_register = HBoxContainer.new()
	_hole_register.name = "HoleRegister"
	_hole_register.add_theme_constant_override("separation", 8)
	_hole_register.size_flags_vertical = Control.SIZE_EXPAND_FILL
	hbox.add_child(_hole_register)

	# The round the holes make is the Course Map's Routing Holes mode, so
	# the tab carries a card that opens the map straight onto it. It is an
	# action rather than a hole, so it stands beside the grid, not in it —
	# and it leads the register on the left, before the hole buttons.
	var map_card := DockActionButton.new()
	map_card.tool_type = "holes_map"
	map_card.tool_name = "Holes Map"
	map_card.glyph = "holes"
	# The Holes tab lives in the Manage section now, so its card wears that
	# section's colour rather than Build's.
	map_card.accent_section = Section.MANAGE
	map_card.tool_description = "The whole course on one map, on Routing Holes: reorder the round, turn a hole, set its par, open or shut it"
	map_card.tool_pressed.connect(_on_tool_button_pressed)
	_hole_register.add_child(map_card)

	# The course scorecard — every hole's par, yardage, stroke index and average,
	# with the course records — used to be a popup of its own. It is the Holes
	# tab's card now, the way the map card opens the Course Map: pressing it
	# swaps the register for the scorecard view, and its back button returns.
	var scorecard_card := DockActionButton.new()
	scorecard_card.name = "ScorecardCard"
	scorecard_card.tool_type = "scorecard"
	scorecard_card.tool_name = "Scorecard"
	scorecard_card.glyph = "holes"
	scorecard_card.accent_section = Section.MANAGE
	scorecard_card.hotkey = "K"
	scorecard_card.tool_description = "The course scorecard: every hole's par, yardage, stroke index and average score, with the course records"
	scorecard_card.tool_pressed.connect(_on_tool_button_pressed)
	_hole_register.add_child(scorecard_card)

	hole_grid = GridContainer.new()
	hole_grid.name = "HoleGrid"
	hole_grid.columns = 1
	hole_grid.add_theme_constant_override("h_separation", 6)
	hole_grid.add_theme_constant_override("v_separation", 4)
	hole_grid.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hole_register.add_child(hole_grid)

	_hole_detail = HBoxContainer.new()
	_hole_detail.name = "HoleDetail"
	_hole_detail.add_theme_constant_override("separation", 14)
	_hole_detail.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_hole_detail.visible = false
	hbox.add_child(_hole_detail)

	_hole_scorecard = CourseScorecardView.new()
	_hole_scorecard.name = "CourseScorecard"
	_hole_scorecard.visible = false
	_hole_scorecard.back_requested.connect(close_course_scorecard)
	hbox.add_child(_hole_scorecard)

## Re-seat the hole buttons so they read three deep down each column before the
## next column starts. main.gd adds and removes one button per hole, but the
## grid fills row-major, so the children are put back into column-major order
## after every change and the grid is widened to exactly the columns they need.
## Each hole row carries its hole number as metadata.
func layout_hole_buttons() -> void:
	if not hole_grid:
		return
	var buttons: Array[Control] = []
	for child in hole_grid.get_children():
		if child is Control and not child.is_queued_for_deletion():
			buttons.append(child)
	buttons.sort_custom(func(a: Control, b: Control) -> bool:
		return int(a.get_meta("hole_number", 0)) < int(b.get_meta("hole_number", 0)))
	for control in buttons:
		if control is Button and not control.has_meta("_hole_detail_bound"):
			control.set_meta("_hole_detail_bound", true)
			control.pressed.connect(func():
				var number := int(control.get_meta("hole_number", 0))
				if number > 0:
					show_hole_detail(number))
	if buttons.is_empty():
		hole_grid.columns = 1
		return
	var column_count := int(ceil(float(buttons.size()) / float(HOLE_COLUMN_HEIGHT)))
	hole_grid.columns = column_count
	var slot := 0
	for row in HOLE_COLUMN_HEIGHT:
		for column in column_count:
			var index := column * HOLE_COLUMN_HEIGHT + row
			if index < buttons.size():
				hole_grid.move_child(buttons[index], slot)
				slot += 1

func _build_golfers_tab(hbox: HBoxContainer) -> void:
	var page := VBoxContainer.new()
	page.add_theme_constant_override("separation", 6)
	hbox.add_child(page)
	_visitor_register = HBoxContainer.new()
	_visitor_register.add_theme_constant_override("separation", 16)
	page.add_child(_visitor_register)
	_visitor_detail = HBoxContainer.new()
	_visitor_detail.add_theme_constant_override("separation", 14)
	page.add_child(_visitor_detail)
	_visitor_shelf = HBoxContainer.new()
	_visitor_shelf.name = "VisitingGolfersShelf"
	_visitor_shelf.add_theme_constant_override("separation", GOLFER_COLUMN_GAP)
	_visitor_register.add_child(_visitor_shelf)

func _build_player_tab(hbox: HBoxContainer) -> void:
	player_tab = PlayerTab.new()
	# Match the terrain shelf, not the full bottom bar (which includes tabs).
	player_tab.custom_minimum_size.y = TerrainTileButton.BUTTON_SIZE.y * 1.5 \
		+ TILE_V_SEPARATION + 2.0 * TILE_V_PADDING
	hbox.add_child(player_tab)

func select_player_section(index: int) -> void:
	if index >= 0 and index < PLAYER_TABS.size():
		select_tab(PLAYER_TABS[index])

## The Club tab is the Manage section's front page: the Maps, Review,
## and Milestone tabs folded into one shelf. Each former tab keeps
## its own labelled column, so its actions still read as a group: the
## company's maps lead, then the course's review and records and its milestones.
## The event Feed sits in Review, beside the other ways of looking back at
## how the course is doing — it used to be a circle in the bottom-left stack.
func _build_club_tab(hbox: HBoxContainer) -> void:
	var groups := [
		["Maps", [
			["course_map", "Land Parcels", "flag", "Shift+M", "The whole course in one isometric map: buy land, reorder the holes, read the golfers' mood, place your staff"],
			["world_map", "World Maps", "maps", "", "Buy, browse and switch between the company's course sites"],
		]],
		["Review", [
			["aura_map", "Review", "review", "", "Course rating, feedback and next steps — now on the Course Map\'s Aura mode"],
			["finance", "Financial Overview", "finance", "F", "Income, expenses, loans and cash flow"],
			["feed", "Feed", "feed", "N", "Course event feed: records, money, weather, tournaments and everything that has happened"],
		]],
		["Milestones", [
			["course_milestones", "Course Milestones", "milestone", "G", "Per-location goals for this save"],
			["world_milestones", "World Milestones", "world", "Shift+G", "Company goals across every course location"],
			["achievements", "Achievements", "achievement", "Shift+T", "Career honours that stay unlocked between saves"],
		]],
	]
	hbox.add_theme_constant_override("separation", 10)
	for group in groups:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		for action in group[1]:
			var button := DockActionButton.new()
			button.tool_type = action[0]
			button.tool_name = action[1]
			button.glyph = action[2]
			button.hotkey = action[3]
			button.tool_description = action[4]
			button.tool_pressed.connect(_on_tool_button_pressed)
			if action[0] == "feed":
				button.name = "FeedBtn"
				button.tooltip_text = "Course event feed (N)"
				feed_button = button
			row.add_child(button)
		hbox.add_child(_make_tab_group(group[0].to_upper(), row, true))
	set_feed_unread_count(feed_unread_count)

## Light the Feed card's unread badge — and the Club tab button's, so the
## count still shows while another Manage tab is open. The bottom dock
## mirrors it onto the Manage section button through
## feed_unread_count_changed, which keeps it visible from any section.
func set_feed_unread_count(count: int) -> void:
	feed_unread_count = count
	if is_instance_valid(feed_button):
		feed_button.notification_count = count
		feed_button.tooltip_text = "Course event feed (N)" if count <= 0 \
			else "Course event feed (N) — %d unread" % count
	var club_tab := _tab_buttons.get(Tab.CLUB) as PixelCircleButton
	if club_tab:
		club_tab.notification_count = count
	feed_unread_count_changed.emit(count)

func _build_staff_tab(hbox: HBoxContainer) -> void:
	# Staff management lives in the tab itself — condition, hire/fire, roster, effects.
	_staff_panel = StaffPanel.new()
	_staff_panel.name = "StaffPanel"
	_staff_panel.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_staff_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_staff_panel.area_move_requested.connect(func(index: int):
		staff_area_move_requested.emit(index))
	hbox.add_child(_staff_panel)
	# The crew's ground is the Course Map's Staff mode, so the tab
	# carries a card that opens the map straight onto it. It is an
	# action rather than a roster row, so it stands beside the panel,
	# not inside it.
	var map_card := DockActionButton.new()
	map_card.tool_type = "staff_map"
	map_card.tool_name = "Staff Map"
	map_card.glyph = "staff"
	map_card.tool_description = "The whole course on one map, on Staff: each employee's ground, and where to hire, post or let them go"
	map_card.tool_pressed.connect(_on_tool_button_pressed)
	hbox.add_child(map_card)

## Reflect the active area-repositioning mode back into the roster buttons.
func set_staff_area_mode_index(index: int) -> void:
	if _staff_panel:
		_staff_panel.set_area_mode_index(index)

# =============================================================================
# Helper Widgets
# =============================================================================

func _make_tab_group(title: String, content: Control, center_content: bool = false) -> VBoxContainer:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	if not title.is_empty():
		var lbl = Label.new()
		lbl.text = title.to_upper()
		lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
		lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
		group.add_child(lbl)

	# Tile grids already carry their own breathing room above and below the
	# rows, so they keep their natural height instead of stretching to fill it.
	if center_content:
		content.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(content)
	return group

func _make_separator() -> VSeparator:
	var sep = VSeparator.new()
	sep.custom_minimum_size = Vector2(1, 28)
	sep.modulate = Color(1, 1, 1, 0.2)
	return sep

func _make_tip_label(text: String) -> Control:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var lbl_title = Label.new()
	lbl_title.text = "INFO"
	lbl_title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl_title.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	group.add_child(lbl_title)

	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	lbl.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(lbl)
	return group

## What a woodland tile does: it paints the species' own ground, and the course
## draws the tree on it. Kept in one place so every species tile says the same.
func _tree_tile_description(tree_type: int) -> String:
	var species := TerrainTypes.get_type_name(tree_type).to_lower()
	var ground := TerrainTypes.get_tree_ground(tree_type)
	return "Woodland: %s canopy over %s. Blocks a shot that finds it, and the " % [species, ground] \
			+ "ball plays badly from among the roots."

func _add_tool_button(parent: Control, tool_def: Dictionary) -> ToolButton:
	var tool_type = tool_def["type"]
	var cost = 0
	var maintenance = 0
	if tool_type is int:
		cost = TerrainTypes.get_placement_cost(tool_type)
		maintenance = TerrainTypes.get_maintenance_cost(tool_type)

	var btn: ToolButton
	var desc := str(tool_def.get("desc", ""))
	# Every Course Terrain paint tile overwrites every other tile on the tab.
	if tool_type is int and TOOL_TAB_MAP.get(tool_type, -1) == Tab.TERRAIN:
		desc = _with_course_tile_replacement(desc)
	if tool_def.get("elevation_preview", false):
		btn = ElevationSelectorButton.new()
		btn.configure(tool_type, tool_def["name"], "", tool_def.get("hotkey", ""),
			desc, cost, maintenance)
		btn.set_brush_square(_elevation_square)
	elif tool_def.get("tile_preview", false):
		btn = TerrainTileButton.new()
		btn.configure(tool_type, tool_def["name"], "", tool_def.get("hotkey", ""),
			desc, cost, maintenance)
	else:
		btn = ToolButton.create(tool_type, tool_def["name"], tool_def.get("icon", ""),
			tool_def.get("hotkey", ""), desc, cost, maintenance)
	btn.tool_pressed.connect(_on_tool_button_pressed)
	parent.add_child(btn)

	if btn is TerrainTileButton:
		btn.custom_minimum_size = (btn as TerrainTileButton).button_size()
		btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	else:
		btn.custom_minimum_size = Vector2(0, TOOL_ROW_HEIGHT)
		btn.size_flags_vertical = Control.SIZE_EXPAND_FILL
		btn.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
		btn.add_theme_constant_override("icon_max_width", 18)

	if not (tool_type is String and _is_menu_action(tool_type)):
		_tool_buttons[tool_type] = btn
		if tool_type is int:
			if tool_type == TerrainTypes.Type.GREEN:
				_green_tile_button = btn as TerrainTileButton
			elif tool_type == TerrainTypes.Type.TEE_BOX:
				_tee_tile_button = btn as TerrainTileButton

	return btn

func _is_menu_action(tool_type: String) -> bool:
	return tool_type in ["course_map", "holes_map", "staff_map", "aura_map", "world_map", "marketing", "course_milestones", "world_milestones", "achievements", "scorecard", "review", "finance", "feed", "tournaments", "play_course"]

func _make_small_group_label(text: String) -> Label:
	var lbl = Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	lbl.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	return lbl

## Brush size stepper row ("-" label "+"), used by the Elevation tab's brush
## group; the caller sets size flags. The Course Terrain tab's brush lives in
## the shelf header's tool row instead (see _build_header_row).
func _create_brush_row() -> HBoxContainer:
	var brush_row = HBoxContainer.new()
	brush_row.alignment = BoxContainer.ALIGNMENT_CENTER
	brush_row.add_theme_constant_override("separation", 3)

	brush_row.add_child(_create_brush_step_button("-", "Smaller brush", _on_brush_decrease))

	var brush_label = Label.new()
	brush_label.text = brush_size_text(_brush_size)
	brush_label.custom_minimum_size = Vector2(30, 0)
	brush_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	brush_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_SM)
	brush_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
	brush_row.add_child(brush_label)
	_brush_labels.append(brush_label)

	brush_row.add_child(_create_brush_step_button("+", "Bigger brush", _on_brush_increase))
	return brush_row

## Round/square brush shape picker. Wears the same PixelCircleButton medallion
## style as InspectButton, and shows a miniature of the brush it will paint —
## the current shape at the current size — instead of a fixed shape glyph.
func _create_brush_shape(cell_size: Vector2 = Vector2(BRUSH_DOCK_CELL, BRUSH_DOCK_CELL)) -> BrushShapeButton:
	var shape := BrushShapeButton.new()
	shape.diameter = cell_size.x
	shape.custom_minimum_size = cell_size
	shape.accent = SECTION_COLORS[Section.BUILD]
	shape.pressed_lights_face = false
	shape.focus_mode = Control.FOCUS_ALL
	shape.toggle_mode = true
	_update_brush_shape_button(shape)
	shape.pressed.connect(_on_brush_shape_toggled)
	_brush_shape_buttons.append(shape)
	return shape

## The brush size readout in the pinned dock: one square cell showing the size
## the selected tool actually paints with. It shares `_brush_labels` with the
## Elevation tab's wider stepper, so both always read the same number.
func _create_brush_size_chip() -> Label:
	var chip := Label.new()
	chip.name = "BrushSizeChip"
	chip.text = brush_size_text(_brush_size)
	chip.custom_minimum_size = Vector2(BRUSH_DOCK_CELL, BRUSH_DOCK_CELL)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chip.add_theme_font_override("font", PixelCircleButton.FONT)
	chip.add_theme_font_size_override("font_size", 14)
	chip.add_theme_color_override("font_color", PixelCircleButton.CREAM)
	chip.add_theme_color_override("font_shadow_color", PixelCircleButton.INK)
	chip.add_theme_constant_override("shadow_offset_x", 0)
	chip.add_theme_constant_override("shadow_offset_y", 2)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override(
		"normal", PixelCircleButton.face_stylebox(int(BRUSH_DOCK_CELL), SECTION_COLORS[Section.BUILD]))
	_brush_labels.append(chip)
	return chip

## One step button of the pinned brush dock (smaller / bigger), wearing the
## same PixelCircleButton medallion style as InspectButton.
func _create_brush_step_button(caption: String, tip: String, action: Callable) -> PixelCircleButton:
	var btn := PixelCircleButton.new()
	btn.diameter = BRUSH_DOCK_CELL
	btn.accent = SECTION_COLORS[Section.BUILD]
	btn.glyph = "minus" if caption == "-" else "plus"
	btn.text = caption
	btn.tooltip_text = tip
	btn.accessibility_name = tip
	btn.accessibility_description = tip
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(action)
	_style_dock_cell(btn)
	_brush_buttons.append(btn)
	return btn

## The brush size stepper as a single row: smaller, the size it paints with,
## bigger. Shared by the header row's Terrain brush controls.
func _create_brush_size_stepper(decrease_action: Callable, increase_action: Callable) -> HBoxContainer:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", int(BRUSH_DOCK_GAP))
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(_create_brush_step_button("-", "Smaller brush", decrease_action))
	group.add_child(_create_brush_size_chip())
	group.add_child(_create_brush_step_button("+", "Bigger brush", increase_action))
	return group

## Round/square elevation brush shape picker for the header row. Like the
## terrain brush shape button, but wired to the Elevation Brush state and
## added to the elevation shape button array so the shared update reaches it.
func _create_elevation_brush_shape_button() -> BrushShapeButton:
	var shape := BrushShapeButton.new()
	shape.diameter = BRUSH_DOCK_CELL
	shape.custom_minimum_size = Vector2(BRUSH_DOCK_CELL, BRUSH_DOCK_CELL)
	shape.accent = SECTION_COLORS[Section.BUILD]
	shape.pressed_lights_face = false
	shape.focus_mode = Control.FOCUS_ALL
	shape.toggle_mode = true
	_update_elevation_brush_shape_button(shape)
	shape.pressed.connect(_on_elevation_brush_shape_toggled)
	_elevation_brush_shape_buttons.append(shape)
	return shape

## One step button of the header row's Elevation Brush size stepper, wearing
## the same PixelCircleButton medallion style as InspectButton.
func _create_elevation_brush_step_button(caption: String, tip: String, action: Callable) -> PixelCircleButton:
	var btn := PixelCircleButton.new()
	btn.diameter = BRUSH_DOCK_CELL
	btn.accent = SECTION_COLORS[Section.BUILD]
	btn.glyph = "minus" if caption == "-" else "plus"
	btn.text = caption
	btn.tooltip_text = tip
	btn.accessibility_name = tip
	btn.accessibility_description = tip
	btn.focus_mode = Control.FOCUS_ALL
	btn.pressed.connect(action)
	_style_dock_cell(btn)
	_elevation_brush_buttons.append(btn)
	return btn

## The elevation brush size readout for the header row: one square cell showing
## the size the Square tool paints with.
func _create_elevation_brush_size_chip() -> Label:
	var chip := Label.new()
	chip.name = "ElevationBrushSizeChip"
	chip.custom_minimum_size = Vector2(BRUSH_DOCK_CELL, BRUSH_DOCK_CELL)
	chip.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	chip.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	chip.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	chip.add_theme_font_override("font", PixelCircleButton.FONT)
	chip.add_theme_font_size_override("font_size", 14)
	chip.add_theme_color_override("font_color", PixelCircleButton.CREAM)
	chip.add_theme_color_override("font_shadow_color", PixelCircleButton.INK)
	chip.add_theme_constant_override("shadow_offset_x", 0)
	chip.add_theme_constant_override("shadow_offset_y", 2)
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_theme_stylebox_override(
		"normal", PixelCircleButton.face_stylebox(int(BRUSH_DOCK_CELL), SECTION_COLORS[Section.BUILD]))
	_elevation_brush_labels.append(chip)
	_update_elevation_brush_label()
	return chip

## The Elevation Brush size stepper as a single row: smaller, the size it
## paints with, bigger. Shared by the header row's Elevation brush controls.
func _create_elevation_brush_size_stepper() -> HBoxContainer:
	var group := HBoxContainer.new()
	group.add_theme_constant_override("separation", int(BRUSH_DOCK_GAP))
	group.mouse_filter = Control.MOUSE_FILTER_IGNORE
	group.add_child(_create_elevation_brush_step_button("-", "Smaller elevation brush", _on_elevation_brush_decrease))
	group.add_child(_create_elevation_brush_size_chip())
	group.add_child(_create_elevation_brush_step_button("+", "Bigger elevation brush", _on_elevation_brush_increase))
	return group

## Give a brush dock cell its fixed footprint matching InspectButton.
func _style_dock_cell(control: Control) -> void:
	control.custom_minimum_size = Vector2(BRUSH_DOCK_CELL, BRUSH_DOCK_CELL)
	if control is PixelCircleButton:
		control.diameter = BRUSH_DOCK_CELL
		control.accent = SECTION_COLORS[Section.BUILD]

func _update_brush_shape_button(btn: Button) -> void:
	var square := not _round_brush
	var shown: int = effective_brush_size()
	if btn is BrushShapeButton:
		(btn as BrushShapeButton).set_brush(shown, square)
	if _round_brush:
		btn.text = "○"
		btn.tooltip_text = "Round brush (Circle), %s %s — click for Square" % [
			shown, "tile" if shown == 1 else "tiles"]
	else:
		btn.text = "□"
		btn.tooltip_text = "Square brush, %s %s — click for Round (Circle)" % [
			shown, "tile" if shown == 1 else "tiles"]
	btn.set_pressed_no_signal(_round_brush)
	btn.accessibility_name = "Brush shape"
	btn.accessibility_description = btn.tooltip_text
	btn.queue_redraw()

func _make_brush_group() -> VBoxContainer:
	var group = VBoxContainer.new()
	group.add_theme_constant_override("separation", 2)
	group.size_flags_vertical = Control.SIZE_EXPAND_FILL

	group.add_child(_make_small_group_label("BRUSH"))

	var shape := _create_brush_shape()
	shape.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(shape)

	var brush_row := _create_brush_row()
	brush_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	group.add_child(brush_row)

	_apply_brush_limit()
	return group

## The sizes the Elevation Brush offers. Flat Square and Gradual Square share
## the same 1x1 through 9x9 list, and the stepper keeps that range even when
## neither Square tool is selected.
func _elevation_brush_sizes() -> Array:
	return ElevationTool.BRUSH_SIZES

func _elevation_brush_size() -> int:
	return _elevation_size

func _elevation_brush_square() -> bool:
	return _elevation_square

## Set the selected elevation selector tool and sync the brush controls: the
## header row controls keep the shared size and shape, and stay enabled whether
## or not a Square tool is selected.
func set_elevation_tool(tool_name: String) -> void:
	_elevation_tool = tool_name
	_update_elevation_brush_group()

## Read back the shared Elevation Brush settings.
func get_elevation_brush_size() -> int:
	return _elevation_brush_size()

func get_elevation_brush_square() -> bool:
	return _elevation_brush_square()

## Mirror the shared brush settings in the header row controls. Size and shape
## stay enabled even when the Vertex tool is selected or no Square tool is
## selected, so the player can set the brush before (or after) picking Flat or
## Gradual.
func _update_elevation_brush_group() -> void:
	for button in _elevation_brush_buttons:
		if is_instance_valid(button):
			button.disabled = false
			button.queue_redraw()
	for shape in _elevation_brush_shape_buttons:
		if is_instance_valid(shape):
			shape.disabled = false
			_update_elevation_brush_shape_button(shape)
	_update_elevation_brush_label()

func _update_elevation_brush_label() -> void:
	var sizes: Array = _elevation_brush_sizes()
	var brush_size: int = _elevation_brush_size()
	if not sizes.is_empty() and not (brush_size in sizes):
		brush_size = sizes.min() if brush_size < sizes.min() else sizes.max()
		_elevation_size = brush_size
	var text := brush_size_text(brush_size)
	for label in _elevation_brush_labels:
		if is_instance_valid(label):
			label.text = text
			label.tooltip_text = "Elevation brush size %s %s" % [text,
				"tile" if brush_size == 1 else "tiles"]
	# The shape plate draws the brush at this size, so it steps with the number.
	for shape in _elevation_brush_shape_buttons:
		if is_instance_valid(shape):
			_update_elevation_brush_shape_button(shape)

func _update_elevation_brush_shape_button(btn: Button) -> void:
	var square := _elevation_brush_square()
	var shown: int = _elevation_brush_size()
	if btn is BrushShapeButton:
		(btn as BrushShapeButton).set_brush(shown, square)
	if square:
		btn.text = "□"
		btn.tooltip_text = "Square elevation brush, %s %s — click for Round" % [
			shown, "tile" if shown == 1 else "tiles"]
	else:
		btn.text = "○"
		btn.tooltip_text = "Round elevation brush, %s %s — click for Square" % [
			shown, "tile" if shown == 1 else "tiles"]
	btn.set_pressed_no_signal(not square)
	btn.accessibility_name = "Elevation brush shape"
	btn.accessibility_description = btn.tooltip_text
	btn.queue_redraw()

func _on_elevation_brush_decrease() -> void:
	var sizes: Array = _elevation_brush_sizes()
	var idx: int = sizes.find(_elevation_brush_size())
	if idx > 0:
		_set_elevation_brush_size(sizes[idx - 1])

func _on_elevation_brush_increase() -> void:
	var sizes: Array = _elevation_brush_sizes()
	var idx: int = sizes.find(_elevation_brush_size())
	if idx >= 0 and idx < sizes.size() - 1:
		_set_elevation_brush_size(sizes[idx + 1])

func _set_elevation_brush_size(value: int) -> void:
	_elevation_size = value
	_update_elevation_brush_label()
	elevation_brush_size_changed.emit(value)

func _on_elevation_brush_shape_toggled() -> void:
	_elevation_square = not _elevation_square
	for tool_name in ["flat", "gradual"]:
		var selector = _tool_buttons.get(tool_name)
		if is_instance_valid(selector) and selector is ElevationSelectorButton:
			selector.set_brush_square(_elevation_square)
	for shape in _elevation_brush_shape_buttons:
		if is_instance_valid(shape):
			_update_elevation_brush_shape_button(shape)
	elevation_brush_shape_changed.emit(_elevation_brush_square())

func _make_review_button() -> Button:
	var review := Button.new()
	review.text = "Review"
	review.tooltip_text = "Course review and next steps"
	review.custom_minimum_size = Vector2(72, TOOL_ROW_HEIGHT)
	review.size_flags_vertical = Control.SIZE_EXPAND_FILL
	review.pressed.connect(func(): course_review_pressed.emit())
	return review

func _make_review_group() -> VBoxContainer:
	var row := HBoxContainer.new()
	row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	row.add_child(_make_review_button())
	return _make_tab_group("REVIEW", row)

func _build_refresh_timer() -> void:
	_refresh_timer = Timer.new()
	_refresh_timer.wait_time = 1.0
	_refresh_timer.autostart = true
	_refresh_timer.timeout.connect(_on_refresh_tick)
	add_child(_refresh_timer)

# =============================================================================
# Costs for special string tools
# =============================================================================

# =============================================================================
# Tab handling
# =============================================================================

func _show_page(tab_index: int) -> void:
	var view_index := Tab.PLAYER if tab_index in PLAYER_TABS else tab_index
	for i in _pages.size():
		_pages[i].visible = i == view_index
	if tab_index in PLAYER_TABS:
		player_tab.select(PLAYER_TABS.find(tab_index))
	if tab_index != Tab.HOLES and _selected_hole > 0:
		hole_detail_changed.emit(0)
	match tab_index:
		Tab.IMPROVEMENTS:
			refresh_decoration_unlocks()
		Tab.HOLES:
			_refresh_holes_tab()
		Tab.GOLFERS:
			_refresh_golfer_lists()
		Tab.PLAYER:
			_refresh_player_skills()
		Tab.STAFF:
			if _staff_panel:
				_staff_panel.refresh()

func select_tab(tab_index: int) -> void:
	if tab_index >= 0 and tab_index < _pages.size():
		expand_section()
		current_tab = tab_index
		_sync_navigation(tab_index)
		_sync_header_row_content()
		_show_page(tab_index)

func _tab_index_for_tool(tool_type) -> int:
	return TOOL_TAB_MAP.get(tool_type, -1)

func _reveal_tab_for_tool(tool_type) -> void:
	var tab_index = _tab_index_for_tool(tool_type)
	if tab_index >= 0:
		select_tab(tab_index)

func _on_refresh_tick() -> void:
	if not is_visible_in_tree():
		return
	if current_tab == Tab.GOLFERS:
		_refresh_golfer_lists()
	elif current_tab == Tab.HOLES and _selected_hole > 0:
		_refresh_holes_tab()
	elif current_tab in PLAYER_TABS:
		_refresh_player_skills()
	elif current_tab == Tab.IMPROVEMENTS:
		# Star rating, reputation and hole count all move during play, so the
		# open decoration shelf keeps up with what has been unlocked.
		refresh_decoration_unlocks()

# =============================================================================
# Holes tab
# =============================================================================

func show_hole_detail(hole_number: int) -> void:
	_scorecard_open = false
	_selected_hole = hole_number
	select_tab(Tab.HOLES)

func close_hole_detail() -> void:
	_selected_hole = 0
	_refresh_holes_tab()

## The Holes tab's Scorecard card and the K shortcut both open the course
## scorecard here. It replaces the hole register, the way a hole's detail does.
func show_course_scorecard() -> void:
	_selected_hole = 0
	_scorecard_open = true
	select_tab(Tab.HOLES)

## Back to the hole register from the scorecard.
func close_course_scorecard() -> void:
	_scorecard_open = false
	_refresh_holes_tab()

## True while the Holes tab is up with the course scorecard showing.
func is_course_scorecard_showing() -> bool:
	return _scorecard_open and current_tab == Tab.HOLES

func _scorecard_showing() -> bool:
	return _scorecard_open and _selected_hole == 0 and current_tab == Tab.HOLES and is_visible_in_tree()

## The scorecard reads the course's holes, scores and records, so any change to
## them rebuilds it while it is on screen. Nothing is rebuilt otherwise.
func _refresh_scorecard_if_showing() -> void:
	if _scorecard_showing():
		_hole_scorecard.refresh()

func _on_hole_event_updated(hole_number: int) -> void:
	if _selected_hole == hole_number:
		_refresh_holes_tab()
	_refresh_scorecard_if_showing()

func _on_hole_event_toggled(hole_number: int, _is_open: bool) -> void:
	if _selected_hole == hole_number:
		_refresh_holes_tab()
	_refresh_scorecard_if_showing()

func _on_hole_event_created(_hole_number: int, _par: int, _distance_yards: int) -> void:
	_refresh_scorecard_if_showing()

func _on_hole_event_deleted(_hole_number: int) -> void:
	_selected_hole = 0
	_refresh_holes_tab()

func _on_holes_event_reordered(_order: Array) -> void:
	_selected_hole = 0
	_refresh_holes_tab()

func _on_hole_event_difficulty_changed(hole_number: int, _difficulty: float) -> void:
	if _selected_hole == hole_number:
		_refresh_holes_tab()
	_refresh_scorecard_if_showing()

func _on_golfer_finished_hole_event(_golfer_id: int, hole_number: int, _strokes: int, _par: int) -> void:
	if _selected_hole == hole_number and is_visible_in_tree() and current_tab == Tab.HOLES:
		_refresh_holes_tab()
	_refresh_scorecard_if_showing()

func _on_record_broken_event(_record_type: String, _golfer_name: String, _value: int, _hole_number: int) -> void:
	_refresh_scorecard_if_showing()

func _on_new_game_reset_holes_tab() -> void:
	_selected_hole = 0
	_scorecard_open = false
	_refresh_holes_tab()

func _on_load_completed_reset_holes_tab(_success: bool) -> void:
	_selected_hole = 0
	_scorecard_open = false
	_refresh_holes_tab()

func _has_hole(hole_number: int) -> bool:
	if hole_number <= 0:
		return false
	if GameManager and GameManager.current_course and not GameManager.current_course.holes.is_empty():
		for hole in GameManager.current_course.holes:
			if hole.hole_number == hole_number:
				return true
		return false
	if hole_grid and hole_grid.find_child("HoleBtn%d" % hole_number, true, false):
		return true
	return false

func _find_hole_data(hole_number: int) -> GameManager.HoleData:
	if GameManager and GameManager.current_course:
		for hole in GameManager.current_course.holes:
			if hole.hole_number == hole_number:
				return hole
	var fallback := GameManager.HoleData.new()
	fallback.hole_number = hole_number
	fallback.par = 4
	fallback.distance_yards = 350
	fallback.difficulty_rating = 3.0
	fallback.is_open = true
	return fallback

func _refresh_holes_tab() -> void:
	if _hole_register == null or _hole_detail == null or _hole_scorecard == null:
		return
	if _selected_hole > 0 and not _has_hole(_selected_hole):
		_selected_hole = 0
	# The hole detail and the scorecard each take the shelf in place of the
	# register; a picked hole wins if both were ever left open.
	var showing_detail := _selected_hole > 0
	var showing_scorecard := _scorecard_open and not showing_detail
	_hole_register.visible = not showing_detail and not showing_scorecard
	_hole_detail.visible = showing_detail
	_hole_scorecard.visible = showing_scorecard
	if showing_detail:
		_show_hole(_selected_hole)
	else:
		_clear_shelf(_hole_detail)
	if showing_scorecard and current_tab == Tab.HOLES:
		_hole_scorecard.refresh()
	hole_detail_changed.emit(_selected_hole if showing_detail and current_tab == Tab.HOLES else 0)

func _show_hole(hole_number: int) -> void:
	_clear_shelf(_hole_detail)
	var hole_data := _find_hole_data(hole_number)
	var tee_orphaned := false
	var green_orphaned := false
	if is_instance_valid(terrain_grid):
		tee_orphaned = terrain_grid.get_tile(hole_data.tee_position) != TerrainTypes.Type.TEE_BOX
		green_orphaned = terrain_grid.get_tile(hole_data.green_position) != TerrainTypes.Type.GREEN

	var back := _visitor_button("< Holes", Color("e2c681"))
	back.name = "BackButton"
	back.tooltip_text = "Return to the course holes list"
	back.pressed.connect(func():
		close_hole_detail())
	_hole_detail.add_child(back)

	var identity := VBoxContainer.new()
	identity.name = "HoleIdentity"
	identity.add_theme_constant_override("separation", 2)
	_hole_detail.add_child(identity)
	identity.add_child(_visitor_label("Hole %d — Par %d" % [hole_data.hole_number, hole_data.par], Color("e2c681")))
	identity.add_child(_visitor_label("OPEN" if hole_data.is_open else "CLOSED",
		Color("83c9a4") if hole_data.is_open else UIConstants.COLOR_WARNING))
	identity.add_child(_visitor_label("%d yards  •  Diff: %.1f" % [hole_data.distance_yards, hole_data.difficulty_rating],
		UIConstants.COLOR_TEXT_MUTED))
	if tee_orphaned or green_orphaned:
		var missing := "tee & green" if tee_orphaned and green_orphaned else ("tee" if tee_orphaned else "green")
		identity.add_child(_visitor_label("Warning: Missing %s" % missing, UIConstants.COLOR_WARNING))
	var locate := _visitor_button("Locate hole", Color("87b9cf"))
	locate.name = "LocateHoleButton"
	locate.tooltip_text = "Center the camera on Hole %d" % hole_data.hole_number
	locate.pressed.connect(func(): hole_locate_requested.emit(hole_data.hole_number))
	identity.add_child(locate)

	var layout_actions := VBoxContainer.new()
	layout_actions.name = "HoleLayoutActions"
	layout_actions.add_theme_constant_override("separation", 4)
	_hole_detail.add_child(layout_actions)

	var tee_label := "Place Tee" if tee_orphaned else "Move Tee"
	var tee_btn := _visitor_button(tee_label, UIConstants.COLOR_WARNING if tee_orphaned else Color("8dba9b"))
	tee_btn.name = "MoveTeeButton"
	if tee_orphaned:
		tee_btn.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	tee_btn.pressed.connect(func(): hole_move_tee_requested.emit(hole_data.hole_number))
	layout_actions.add_child(tee_btn)

	var green_label := "Place Green" if green_orphaned else "Move Green"
	var green_btn := _visitor_button(green_label, UIConstants.COLOR_WARNING if green_orphaned else Color("8dba9b"))
	green_btn.name = "MoveGreenButton"
	if green_orphaned:
		green_btn.add_theme_color_override("font_color", UIConstants.COLOR_WARNING)
	green_btn.pressed.connect(func(): hole_move_green_requested.emit(hole_data.hole_number))
	layout_actions.add_child(green_btn)

	var auto_par := GolfRules.calculate_par(hole_data.distance_yards)
	var par_text := "Par %d" % hole_data.par
	if hole_data.par_override > 0:
		par_text += "*"
	else:
		par_text += " (auto)"
	var par_btn := _visitor_button("Cycle Par  [%s]" % par_text, Color("d8bb71"))
	par_btn.name = "CycleParButton"
	par_btn.pressed.connect(func():
		var new_par := _cycle_hole_par(hole_data.par, auto_par)
		hole_par_override_requested.emit(hole_data.hole_number, new_par))
	layout_actions.add_child(par_btn)

	var state_actions := VBoxContainer.new()
	state_actions.name = "HoleStateActions"
	state_actions.add_theme_constant_override("separation", 4)
	_hole_detail.add_child(state_actions)

	var toggle_label := "Close Hole" if hole_data.is_open else "Open Hole"
	var toggle_color := UIConstants.COLOR_DANGER if hole_data.is_open else UIConstants.COLOR_SUCCESS
	var toggle_btn := _visitor_button(toggle_label, toggle_color)
	toggle_btn.name = "ToggleHoleButton"
	toggle_btn.add_theme_color_override("font_color", toggle_color)
	toggle_btn.pressed.connect(func(): hole_toggle_requested.emit(hole_data.hole_number))
	state_actions.add_child(toggle_btn)

	var sep := HSeparator.new()
	sep.add_theme_constant_override("separation", 4)
	sep.add_theme_stylebox_override("separator", StyleBoxLine.new())
	state_actions.add_child(sep)

	var delete_btn := _visitor_button("Delete Hole", UIConstants.COLOR_DANGER)
	delete_btn.name = "DeleteHoleButton"
	delete_btn.add_theme_color_override("font_color", UIConstants.COLOR_DANGER)
	delete_btn.add_theme_color_override("font_hover_color", UIConstants.COLOR_DANGER_DIM)
	delete_btn.tooltip_text = "Remove Hole %d and renumber the holes after it. Asks first." \
		% hole_data.hole_number
	delete_btn.pressed.connect(func(): hole_delete_requested.emit(hole_data.hole_number))
	state_actions.add_child(delete_btn)

	var info_col := VBoxContainer.new()
	info_col.name = "HoleInformation"
	info_col.add_theme_constant_override("separation", 2)
	_hole_detail.add_child(info_col)
	info_col.add_child(_visitor_label("Hole Information", Color("87b9cf")))
	info_col.add_child(_visitor_label("Par: %s  •  Distance: %d yards" % [par_text.trim_prefix("Par "), hole_data.distance_yards]))
	var diff_color := _hole_difficulty_color(hole_data.difficulty_rating)
	info_col.add_child(_visitor_label("Rating: %.1f  •  Difficulty: %.1f / 10" % [
		hole_data.difficulty_rating, hole_data.difficulty_rating], diff_color))
	var rev_text := "$%s" % _format_hole_number(hole_data.total_revenue) if hole_data.total_revenue > 0 else "No revenue yet"
	var rev_color := UIConstants.COLOR_SUCCESS if hole_data.total_revenue > 0 else UIConstants.COLOR_TEXT_MUTED
	info_col.add_child(_visitor_label("Revenue: %s" % rev_text, rev_color))
	if hole_data.stroke_index > 0:
		info_col.add_child(_visitor_label("Stroke Index: %d" % hole_data.stroke_index))

	var stats: GameManager.HoleStatistics = GameManager.get_hole_statistics(hole_data.hole_number) if GameManager else null
	var scoring_col := VBoxContainer.new()
	scoring_col.name = "ScoringStatistics"
	scoring_col.add_theme_constant_override("separation", 2)
	_hole_detail.add_child(scoring_col)
	scoring_col.add_child(_visitor_label("Scoring Statistics", Color("87b9cf")))
	if stats and stats.total_rounds > 0:
		scoring_col.add_child(_visitor_label("Rounds Played: %d" % stats.total_rounds))
		var avg_score: float = stats.get_average_score()
		var avg_to_par: float = stats.get_average_to_par(hole_data.par)
		var avg_color := UIConstants.COLOR_SUCCESS if avg_to_par <= 0.0 else UIConstants.COLOR_WARNING
		if avg_to_par > 0.5:
			avg_color = UIConstants.COLOR_DANGER
		var avg_text := "%.2f" % avg_score
		if avg_to_par != 0.0:
			avg_text += " (%s%.2f)" % ["+" if avg_to_par > 0.0 else "", avg_to_par]
		scoring_col.add_child(_visitor_label("Average Score: %s" % avg_text, avg_color))
		if stats.best_score > 0:
			var best_color := UIConstants.COLOR_GOLD if stats.best_score == 1 else UIConstants.COLOR_INFO
			scoring_col.add_child(_visitor_label("Best Score: %d" % stats.best_score, best_color))

		var dist_entries: Array = []
		if stats.holes_in_one > 0:
			dist_entries.append(["Holes-in-One: %d" % stats.holes_in_one, UIConstants.COLOR_GOLD])
		if stats.eagles > 0:
			dist_entries.append(["Eagles: %d" % stats.eagles, UIConstants.COLOR_GOLD_DIM])
		if stats.birdies > 0:
			dist_entries.append(["Birdies: %d" % stats.birdies, UIConstants.COLOR_INFO])
		dist_entries.append(["Pars: %d" % stats.pars, UIConstants.COLOR_TEXT_DIM])
		if stats.bogeys > 0:
			dist_entries.append(["Bogeys: %d" % stats.bogeys, UIConstants.COLOR_DANGER_MUTED])
		if stats.double_bogeys_plus > 0:
			dist_entries.append(["Double+: %d" % stats.double_bogeys_plus, UIConstants.COLOR_DANGER])

		var dist_col: VBoxContainer = null
		for i in dist_entries.size():
			if i % 4 == 0:
				dist_col = VBoxContainer.new()
				dist_col.name = "ScoreDistribution" if i == 0 else "ScoreDistributionContinued"
				dist_col.add_theme_constant_override("separation", 2)
				_hole_detail.add_child(dist_col)
				dist_col.add_child(_visitor_label("Score Distribution" + (" (continued)" if i > 0 else ""), Color("87b9cf")))
			dist_col.add_child(_visitor_label(str(dist_entries[i][0]), dist_entries[i][1]))
	else:
		scoring_col.add_child(_visitor_label("No rounds played yet", UIConstants.COLOR_TEXT_MUTED))

func _hole_difficulty_color(difficulty: float) -> Color:
	if difficulty < 4.0:
		return UIConstants.COLOR_SUCCESS
	elif difficulty < 7.0:
		return UIConstants.COLOR_WARNING
	return UIConstants.COLOR_DANGER

func _cycle_hole_par(current_par: int, auto_par: int) -> int:
	var min_par: int = maxi(3, auto_par - 1)
	var max_par: int = mini(6, auto_par + 1)
	var next_par: int = current_par + 1
	if next_par > max_par:
		next_par = min_par
	return next_par

func _format_hole_number(n: int) -> String:
	var s := str(n)
	var result := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		if count > 0 and count % 3 == 0:
			result = "," + result
		result = s[i] + result
		count += 1
	return result

# =============================================================================
# Golfer tab
# =============================================================================

func record_completed_round(data: Dictionary) -> void:
	_visitor_archive[str(data.get("name", "Golfer"))] = data.duplicate(true)
	if is_visible_in_tree() and current_tab == Tab.GOLFERS:
		_refresh_golfer_lists()

func _refresh_golfer_lists() -> void:
	if _visitor_shelf == null:
		return

	# The old columns leave their shelves straight away. A child waiting on
	# queue_free() is still in the tree, so it would still take up shelf space
	# and sit beside the fresh columns until the end of the frame.
	_clear_shelf(_visitor_shelf)

	var rows: Array = []
	if golfer_data_provider.is_valid():
		rows = golfer_data_provider.call()

	var active_names: Dictionary = {}
	for row_data in rows:
		var visitor_name := str(row_data.get("name", "Golfer"))
		active_names[visitor_name] = true
		var snapshot: Dictionary = _visitor_archive.get(visitor_name, {}).duplicate(true)
		snapshot.merge(row_data, true)
		_visitor_archive[visitor_name] = snapshot
	_visitor_register.visible = _selected_visitor.is_empty()
	_visitor_detail.visible = not _selected_visitor.is_empty()
	if not _selected_visitor.is_empty():
		_show_visitor(_selected_visitor, active_names.has(_selected_visitor))
	var golfer_rows: Array[Control] = []
	for row_data in rows:
		golfer_rows.append(_make_golfer_row(row_data))
	for visitor_name in _visitor_archive:
		if not active_names.has(visitor_name):
			golfer_rows.append(_make_visitor_card(_visitor_archive[visitor_name], false))
	if golfer_rows.is_empty():
		golfer_rows.append(_make_empty_label("Your next regular starts here.\nGolfers will appear when they visit your course."))
	_stack_in_columns(_visitor_shelf, golfer_rows, GOLFER_COLUMN_HEIGHT, GOLFER_ROW_GAP)

## Take every column off a shelf. The columns are only removed here and freed at
## the end of the frame, so a refresh can never free a row out from under a
## signal it is still emitting.
func _clear_shelf(shelf: HBoxContainer) -> void:
	for child in shelf.get_children():
		shelf.remove_child(child)
		child.queue_free()

## Fill a shelf with items stacked column_height deep: the first column takes
## the first column_height items, the next column takes the next, and so on.
## Each column is a VBox of its own, so a short last column never pulls the
## items above it across — the way a GridContainer, which counts its rows off
## the children it is given, would. The columns run off to the right where the
## page already scrolls, so the tab never grows past the bottom bar's height.
func _stack_in_columns(shelf: HBoxContainer, items: Array[Control], column_height: int,
		row_gap: int) -> void:
	var column: VBoxContainer = null
	for index in items.size():
		if index % column_height == 0:
			column = VBoxContainer.new()
			column.add_theme_constant_override("separation", row_gap)
			column.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
			shelf.add_child(column)
		column.add_child(items[index])

func _make_empty_label(text: String) -> Label:
	var label = Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_XS)
	label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	return label

func _visitor_label(text: String, color := Color("e4e7d5")) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", color)
	return label

func _visitor_button(text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.add_theme_font_size_override("font_size", 12)
	PixelButtonStyle.paint_card(button, accent, 0, 6, Color("e4e7d5"), Color.WHITE)
	return button

func _make_golfer_row(row_data: Dictionary) -> Control:
	return _make_visitor_card(row_data, true)

func _make_round_row(round_data: Dictionary) -> Control:
	return _make_visitor_card(round_data, false)

func _make_visitor_card(data: Dictionary, active: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	var accent := Color("83c9a4") if active else Color("b5a477")
	var portrait := VisitorPortrait.new()
	portrait.texture = data.get("portrait")
	row.add_child(portrait)
	var name_text := str(data.get("name", "Golfer"))
	var subtitle := "PLAYING  /  H%02d  /  %d strokes" % [data.get("hole", 1), data.get("strokes", 0)] if active else "PAST VISITOR  /  %d strokes" % data.get("strokes", 0)
	var button := _visitor_button(name_text + "\n" + subtitle, accent)
	button.custom_minimum_size = Vector2(260, 44)
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	button.tooltip_text = "View %s's profile" % name_text
	button.pressed.connect(func():
		_selected_visitor = name_text
		_refresh_golfer_lists())
	row.add_child(button)
	if active:
		var locate := _visitor_button("Locate", Color("87b9cf"))
		locate.custom_minimum_size.y = 44
		locate.tooltip_text = "Center the camera on " + name_text
		locate.pressed.connect(_on_golfer_row_pressed.bind(data.get("id", -1)))
		row.add_child(locate)
	return row

func _show_visitor(visitor_name: String, active: bool) -> void:
	_clear_shelf(_visitor_detail)
	var data: Dictionary = _visitor_archive.get(visitor_name, {})
	var back := _visitor_button("< Guest register", Color("e2c681"))
	back.pressed.connect(func():
		_selected_visitor = ""
		_refresh_golfer_lists())
	_visitor_detail.add_child(back)
	var portrait := VisitorPortrait.new()
	portrait.texture = data.get("portrait")
	_visitor_detail.add_child(portrait)
	var identity := VBoxContainer.new()
	_visitor_detail.add_child(identity)
	identity.add_child(_visitor_label(visitor_name, Color("e2c681")))
	identity.add_child(_visitor_label(GolferTier.get_tier_name(data.get("tier", 1))))
	identity.add_child(_visitor_label("ON THE COURSE" if active else "PAST VISITOR", Color("83c9a4")))
	identity.add_child(_visitor_label("Strokes: %d" % data.get("strokes", 0)))
	if active:
		identity.add_child(_visitor_label("Hole: %d  /  Attitude: %d%%" % [data.get("hole", 1), int(float(data.get("attitude", 0.5)) * 100)]))
		var locate := _visitor_button("Locate golfer", Color("87b9cf"))
		locate.pressed.connect(_on_golfer_row_pressed.bind(data.get("id", -1)))
		identity.add_child(locate)
	elif data.has("day"):
		identity.add_child(_visitor_label("Last round: " + GameCalendar.format_date_short(data.day)))
		var diff := int(data.get("strokes", 0)) - int(data.get("par", 0))
		identity.add_child(_visitor_label("Score: %+d to par" % diff, UIConstants.get_score_color(diff)))
	for section in data.get("profile", []):
		var lines: Array = section.get("lines", [])
		var column: VBoxContainer
		# Short, horizontally scrolling columns keep the dock's height fixed.
		for index in maxi(lines.size(), 1):
			if index % 4 == 0:
				column = VBoxContainer.new()
				column.custom_minimum_size.x = 230
				column.add_theme_constant_override("separation", 4)
				var scroll := ScrollContainer.new()
				scroll.custom_minimum_size = Vector2(290, 150)
				scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
				_visitor_detail.add_child(scroll)
				column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
				scroll.add_child(column)
				column.add_child(_visitor_label(str(section.get("title", "Profile")) + (" (continued)" if index > 0 else ""), Color("87b9cf")))
			if index < lines.size():
				var label := _visitor_label(str(lines[index]))
				label.custom_minimum_size.x = 260
				label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
				column.add_child(label)
		var meters: Dictionary = section.get("meters", {})
		for meter_name in meters:
			var row := HBoxContainer.new()
			column.add_child(row)
			var label := _visitor_label("%s: %d%%" % [meter_name, int(float(meters[meter_name]) * 100)])
			label.custom_minimum_size.x = 110
			row.add_child(label)
			var bar := ProgressBar.new()
			bar.custom_minimum_size = Vector2(100, 12)
			bar.max_value = 1.0
			bar.value = float(meters[meter_name])
			bar.show_percentage = false
			row.add_child(bar)

func show_visitor_profile(visitor_name: String) -> void:
	_selected_visitor = visitor_name
	select_tab(Tab.GOLFERS)

func _on_golfer_row_pressed(golfer_id: int) -> void:
	if golfer_id >= 0:
		golfer_row_clicked.emit(golfer_id)

# =============================================================================
# Player tab
# =============================================================================

## The Player tab's skill readout belongs to PlayerRoundManager's Player Skills
## page; all the toolbar keeps in step is the badge on the Player Skills button,
## which counts the points still to spend.
func _refresh_player_skills() -> void:
	if is_instance_valid(player_tab):
		player_tab.refresh_skill_badge()

# =============================================================================
# Tool selection
# =============================================================================

func _on_tool_button_pressed(tool_type) -> void:
	# Tee Box is unselectable while an unused tee waits on the course.
	if tool_type is int and tool_type == TerrainTypes.Type.TEE_BOX and not _tee_box_can_place:
		if _current_tool == TerrainTypes.Type.TEE_BOX:
			clear_selection()
		return

	_reveal_tab_for_tool(tool_type)

	if tool_type is int:
		_current_tool = tool_type
		_selected_string_tool = ""
		_update_selection_highlight()
		tool_selected.emit(tool_type)
	else:
		match tool_type:
			"building":
				building_placement_pressed.emit()
			"decoration":
				decoration_placement_pressed.emit()
			"open_hole":
				open_hole_pressed.emit()
			"vertex":
				elevation_tool_pressed.emit("vertex")
			"flat":
				elevation_tool_pressed.emit("flat")
			"gradual":
				elevation_tool_pressed.emit("gradual")
			"bulldozer":
				bulldozer_pressed.emit()
			"play_course":
				play_course_pressed.emit()
			"tournaments":
				tournaments_pressed.emit()
			"course_map":
				course_map_pressed.emit()
			"holes_map":
				holes_map_pressed.emit()
			"staff_map":
				staff_map_pressed.emit()
			"aura_map":
				# Review now lives in Aura mode, keep legacy signal for compatibility
				course_review_pressed.emit()
				aura_map_pressed.emit()
			"world_map":
				world_map_pressed.emit()
			"marketing":
				marketing_pressed.emit()
			"course_milestones":
				course_milestones_pressed.emit()
			"world_milestones":
				world_milestones_pressed.emit()
			"achievements":
				achievements_pressed.emit()
			"scorecard":
				show_course_scorecard()
			"review":
				# Legacy Review button now opens Aura mode (full review lives there)
				course_review_pressed.emit()
				aura_map_pressed.emit()
			"finance":
				financial_overview_pressed.emit()
			"feed":
				event_feed_pressed.emit()

func _update_selection_highlight() -> void:
	for tool_type in _tool_buttons.keys():
		var btn = _tool_buttons[tool_type]
		if is_instance_valid(btn) and btn is ToolButton:
			var is_match = false
			if typeof(tool_type) == typeof(_current_tool) and tool_type == _current_tool:
				is_match = true
			elif not _selected_string_tool.is_empty() and str(tool_type) == _selected_string_tool:
				is_match = true
			btn.set_selected(is_match)

func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		return

	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return

	if not (event is InputEventKey and event.pressed and not event.echo):
		return

	var focused = get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit:
		return

	var action := InputBindings.action_for_event(event, TOOL_SHORTCUTS)
	if action.is_empty():
		return

	match action:
		"terrain_fairway":
			_on_tool_button_pressed(TerrainTypes.Type.FAIRWAY)
		"terrain_rough":
			_on_tool_button_pressed(TerrainTypes.Type.ROUGH)
		"terrain_green":
			_on_tool_button_pressed(TerrainTypes.Type.GREEN)
		"terrain_tee":
			_on_tool_button_pressed(TerrainTypes.Type.TEE_BOX)
		"terrain_bunker":
			_on_tool_button_pressed(TerrainTypes.Type.BUNKER)
		"terrain_water":
			_on_tool_button_pressed(TerrainTypes.Type.WATER)
		"terrain_out_of_bounds":
			_on_tool_button_pressed(TerrainTypes.Type.OUT_OF_BOUNDS)
		"terrain_path":
			_on_tool_button_pressed(TerrainTypes.WALKING_PATH_TOOL)
		"terrain_firm_fairway":
			_on_tool_button_pressed(TerrainTypes.Type.FIRM_FAIRWAY)
		"terrain_waste_bunker":
			_on_tool_button_pressed(TerrainTypes.Type.WASTE_BUNKER)
		"terrain_deep_rough":
			_on_tool_button_pressed(TerrainTypes.Type.DEEP_ROUGH)
		"terrain_pot_bunker":
			_on_tool_button_pressed(TerrainTypes.Type.POT_BUNKER)
		"terrain_stream":
			_on_tool_button_pressed(TerrainTypes.Type.STREAM)
		"terrain_rocks":
			_on_tool_button_pressed(TerrainTypes.Type.ROCKS)
		"terrain_brush":
			_on_tool_button_pressed(TerrainTypes.Type.BRUSH)
		"terrain_small_boulders":
			_on_tool_button_pressed(TerrainTypes.Type.SMALL_BOULDERS)
		"terrain_large_boulders":
			_on_tool_button_pressed(TerrainTypes.Type.LARGE_BOULDERS)
		"terrain_flowers":
			select_tab(Tab.TERRAIN)
			_on_tool_button_pressed(TerrainTypes.Type.FLOWER_BED)
		"tool_trees":
			select_tab(Tab.TERRAIN)
			var theme_trees: Array = CourseTheme.get_tree_types(GameManager.current_theme)
			if not theme_trees.is_empty():
				_on_tool_button_pressed(theme_trees[0])
		"tool_building":
			_on_tool_button_pressed("building")
		"tool_decoration":
			_on_tool_button_pressed("decoration")
		"tool_open_hole":
			_on_tool_button_pressed("open_hole")
		"tool_bulldozer":
			_on_tool_button_pressed("bulldozer")
		"tab_terrain":
			select_tab(Tab.TERRAIN)
		"tab_improvements":
			select_tab(Tab.IMPROVEMENTS)
		"tab_elevation":
			select_tab(Tab.ELEVATION)
		"elevation_vertex":
			select_tab(Tab.ELEVATION)
			_on_tool_button_pressed("vertex")
		"elevation_flat":
			select_tab(Tab.ELEVATION)
			_on_tool_button_pressed("flat")
		"elevation_gradual":
			select_tab(Tab.ELEVATION)
			_on_tool_button_pressed("gradual")
		_:
			return
	get_viewport().set_input_as_handled()

# =============================================================================
# Public API
# =============================================================================

func set_current_tool(tool_type: int) -> void:
	# Prevent selecting Tee when an unused tee waits.
	if tool_type == TerrainTypes.Type.TEE_BOX and not _tee_box_can_place:
		clear_selection()
		return
	_current_tool = tool_type
	_selected_string_tool = ""
	_update_selection_highlight()

func get_current_tool() -> int:
	return _current_tool

func clear_selection() -> void:
	_current_tool = -1
	_selected_string_tool = ""
	_update_selection_highlight()

func has_selection() -> bool:
	return (_current_tool >= 0 and _current_tool in _tool_buttons) or (not _selected_string_tool.is_empty() and _selected_string_tool in _tool_buttons)

func get_brush_size() -> int:
	return _brush_size

func _on_brush_shape_selected(index: int) -> void:
	# Kept for compatibility; OptionButton no longer used — toggle maps 0=round, 1=square.
	_round_brush = index == 0
	for button in _brush_shape_buttons:
		if is_instance_valid(button):
			_update_brush_shape_button(button)
	brush_shape_changed.emit(_round_brush)

func _on_brush_shape_toggled() -> void:
	_round_brush = not _round_brush
	for button in _brush_shape_buttons:
		if is_instance_valid(button):
			_update_brush_shape_button(button)
	brush_shape_changed.emit(_round_brush)

func _on_brush_decrease() -> void:
	var idx = BRUSH_SIZES.find(_brush_size)
	if idx > 0:
		_brush_size = BRUSH_SIZES[idx - 1]
		_update_brush_label()
		brush_size_changed.emit(_brush_size)

func _on_brush_increase() -> void:
	var idx = BRUSH_SIZES.find(_brush_size)
	if idx < BRUSH_SIZES.size() - 1:
		_brush_size = BRUSH_SIZES[idx + 1]
		_update_brush_label()
		brush_size_changed.emit(_brush_size)

func _update_brush_label() -> void:
	var shown: int = effective_brush_size()
	var text := brush_size_text(shown)
	for label in _brush_labels:
		if is_instance_valid(label):
			label.text = text
			label.tooltip_text = "Brush size %s %s" % [text,
				"tile" if shown == 1 else "tiles"]
	# The shape plate draws the brush at this size, so it steps with the number.
	for shape in _brush_shape_buttons:
		if is_instance_valid(shape):
			_update_brush_shape_button(shape)

## The brush size the selected tool actually paints with. Tee boxes, and a green
## that is about to become a Green With Hole, are capped at a single tile.
func effective_brush_size() -> int:
	if _brush_limit != HoleLayout.UNLIMITED_BRUSH:
		return mini(_brush_size, _brush_limit)
	return _brush_size

## Cap (or uncap) the brush for the selected tool: 1 = single tile, 0 = no cap.
func set_brush_limit(limit: int) -> void:
	if _brush_limit == limit:
		return
	_brush_limit = limit
	_apply_brush_limit()

func _apply_brush_limit() -> void:
	var locked: bool = _brush_limit == 1
	for button in _brush_buttons:
		if is_instance_valid(button):
			button.disabled = locked
			button.queue_redraw()
	for shape in _brush_shape_buttons:
		if is_instance_valid(shape):
			shape.disabled = locked
			shape.queue_redraw()
	_update_brush_label()

func set_brush_size(value: int) -> void:
	if value in BRUSH_SIZES:
		_brush_size = value
		_update_brush_label()
		brush_size_changed.emit(value)

## Keep the Green tile's flag and tooltip in sync with what the next green paints.
func set_green_placement_state(places_cup: bool) -> void:
	_green_places_cup = places_cup
	if not is_instance_valid(_green_tile_button):
		return
	_green_tile_button.set_green_places_cup(places_cup)
	if places_cup:
		_green_tile_button.tool_description = _with_course_tile_replacement(
				"The next placement will be a Green With Hole: one tile with a cup and flag.")
	else:
		_green_tile_button.tool_description = _with_course_tile_replacement(
				"The next placement will be a Green Without Hole. It uses the selected brush and adds no cup.")
	_green_tile_button.accessibility_description = "%s Shortcut %s." % [
		_green_tile_button.tool_description, _green_tile_button.hotkey]

## Append the shared replacement sentence without doubling it.
func _with_course_tile_replacement(desc: String) -> String:
	var sentence := TerrainTypes.REPLACES_ANY_COURSE_TILE
	if desc.contains(sentence):
		return desc
	if desc.is_empty():
		return sentence
	return desc + " " + sentence

func green_will_place_cup() -> bool:
	return _green_places_cup

## Enable/disable the Open Hole buttons and explain what is still missing. The
## nestled diamond draws its ring from the button's state — gold while a tee and
## a cup are waiting — so it is repainted here, after the switch.
func set_open_hole_state(can_open: bool, reason: String = "") -> void:
	for button in _open_hole_buttons:
		if not is_instance_valid(button):
			continue
		button.disabled = not can_open
		button.tool_description = OPEN_HOLE_TOOLTIP if can_open or reason.is_empty() \
				else "%s. %s" % [OPEN_HOLE_BLOCKED_TOOLTIP, reason]
		button._update_visual_state()

## Grey out, unselect and make unselectable the Tee tile while an unused tee waits.
func set_tee_box_state(can_place: bool, reason: String = "") -> void:
	_tee_box_can_place = can_place
	_tee_box_blocker = reason
	var btn: ToolButton = _tool_buttons.get(TerrainTypes.Type.TEE_BOX, null) as ToolButton
	if not is_instance_valid(btn):
		btn = _tee_tile_button
	if not is_instance_valid(btn):
		return

	# If the tee was selected and now becomes unavailable, unselect it.
	if not can_place and _current_tool == TerrainTypes.Type.TEE_BOX:
		clear_selection()

	btn.disabled = not can_place

	# Greyed out visual — modulate plus outline handled in TerrainTileButton,
	# but also set here so the change is immediate even if _update_visual_state
	# hasn't run yet.
	if not can_place:
		btn.modulate = Color(0.45, 0.45, 0.45, 0.65)
		var base_desc := "Tee for one hole — a single tile (1x1). Only one tee box may wait on the course at a time"
		if not reason.is_empty():
			btn.tool_description = "%s (%s)" % [base_desc, reason]
		else:
			btn.tool_description = "%s (Blocked — a tee box is already waiting. Open the hole first (H).)" % base_desc
	else:
		btn.modulate = Color(1, 1, 1, 1)
		btn.tool_description = "Tee for one hole — a single tile (1x1). Only one tee box may wait on the course at a time"

	btn.accessibility_description = "%s Shortcut %s." % [btn.tool_description, btn.hotkey]

	# Ensure the diamond outline reflects the disabled state immediately.
	btn._update_visual_state()

func set_view_state(_orientation: int, _isometric: bool) -> void:
	pass
