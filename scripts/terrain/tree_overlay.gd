extends Node2D
class_name TreeOverlay
## TreeOverlay - draws the standing trees that grow on every woodland tile
##
## Woodland is painted, not planted. A Pine Tree tile is one terrain id, laid
## and replaced like Rocks or Wild Flowers, so there is no tree to place, to
## own, to clear or to undo: the tile is the tree. The course surface keeps the
## turf a grove shares with its neighbours (see `tile_at()` in
## `course_surface.gdshader`) and this overlay paints the canopies over it —
## one CanvasItem drawing one tree per tile, no node per tree, exactly as
## FlowerOverlay paints a bed of wild flowers.
##
## A tile's species is its own terrain id's; the generic `Type.TREES` tile —
## the ground older saves carry, and what the generators paint when they want a
## wood rather than a plantation — picks from the course theme's species, seeded
## from the tile's coordinates so the mix is varied yet identical every time the
## course loads.
##
## Every species is drawn from four angles — `<species>_n.png`, `_e`, `_s` and
## `_w` — and the overlay paints the one the course is being viewed from, the
## way a building swaps its sprite when the view turns (see BuildingSprites).
## The four views are generated from the one authored (unsuffixed, north)
## drawing by `tools/tree_art/generate.py`; a species missing a view falls
## back to that drawing, so new art is playable before its angles exist.

## Species art lives here: `<species>.png` plus its four `_n/_e/_s/_w` views,
## with `spring/`, `fall/` and `winter/` variants for the ones that change
## with the calendar.
const SPRITE_DIR := "res://assets/sprites/trees/"

## The four angles a tree is drawn from, indexed by view orientation (see
## TerrainGrid.get_view_orientation()): 0 is the course compass's north — the
## default view, whose art is the authored drawing — then a quarter turn
## clockwise per step through east and south to west.
const FACINGS: Array[String] = ["n", "e", "s", "w"]

## The angle drawn when nothing names one: the authored north view. It is
## what the toolbar's tree tiles preview, so a button never turns with the
## course behind it.
const DEFAULT_FACING := 0

## Species whose foliage turns with the season, so their art is looked up in a
## season folder. Everything else is evergreen and wears one sprite all year.
const DECIDUOUS_SPECIES: Array[String] = ["oak", "maple", "birch"]

## Themes cold enough for snow to lie on a pine through winter.
const SNOWY_THEMES: Array[int] = [
	CourseTheme.Type.PARKLAND, CourseTheme.Type.MOUNTAIN, CourseTheme.Type.HEATHLAND,
]

## How far above a sprite's centre its trunk meets the ground, so a tree stands
## on its tile instead of floating half a tile above it.
const SPRITE_BASE_OFFSETS: Dictionary = {
	"oak": 22.0, "pine": 32.0, "maple": 20.0, "birch": 25.0, "palm": 22.0,
	"bush": 12.0, "cactus": 24.0, "fescue": 10.0, "cattails": 16.0,
	"dead_tree": 28.0, "heather": 10.0,
}

## The silhouette painted when a species has no art on this machine: enough of
## a tree to read at a glance, in the species' own color.
const CANOPY_SHAPES: Dictionary = {
	"pine": "conifer",
	"oak": "broadleaf", "maple": "broadleaf", "birch": "broadleaf",
	"palm": "fan", "dead_tree": "bare", "cactus": "column",
	"bush": "mound", "heather": "mound", "fescue": "tuft", "cattails": "reed",
}

## A tree is not planted dead centre: a little lean and size change per tile is
## what makes a wood look grown rather than laid out.
const JITTER_X := 6.0
const JITTER_Y := 3.0
const SCALE_MIN := 0.85
const SCALE_MAX := 1.15

var terrain_grid: TerrainGrid
var _tree_tiles: Dictionary = {}  # Vector2i -> species key drawn on that tile

static var _texture_cache: Dictionary = {}  # sprite path -> Texture2D (or null)

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	# Woodland is ground cover: it sits under the entities and their shadows, so
	# a golfer walking past a tree is never hidden by its crown. It is the top of
	# that ground band, painted over the walking trail and every other mark laid
	# on the turf — a tree stands where it was planted, whatever was trodden
	# through it (see TerrainGrid.GROUND_DETAIL_ORDER).
	z_index = 1
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rescan()
	EventBus.terrain_tile_changed.connect(_on_terrain_tile_changed)
	EventBus.load_completed.connect(_on_load_completed)
	EventBus.season_changed.connect(_on_season_changed)
	EventBus.theme_changed.connect(_on_theme_changed)
	EventBus.view_rotated.connect(_on_view_rotated)

func _exit_tree() -> void:
	if EventBus.terrain_tile_changed.is_connected(_on_terrain_tile_changed):
		EventBus.terrain_tile_changed.disconnect(_on_terrain_tile_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)
	if EventBus.season_changed.is_connected(_on_season_changed):
		EventBus.season_changed.disconnect(_on_season_changed)
	if EventBus.theme_changed.is_connected(_on_theme_changed):
		EventBus.theme_changed.disconnect(_on_theme_changed)
	if EventBus.view_rotated.is_connected(_on_view_rotated):
		EventBus.view_rotated.disconnect(_on_view_rotated)

## Rebuild every woodland tile from scratch: after a load, a generated course,
## or a theme change that moved the species mix under us.
func rescan() -> void:
	_tree_tiles.clear()
	if terrain_grid:
		for x in range(terrain_grid.grid_width):
			for y in range(terrain_grid.grid_height):
				var pos := Vector2i(x, y)
				var type: int = terrain_grid.get_tile(pos)
				if TerrainTypes.is_tree(type):
					_tree_tiles[pos] = species_at(type, pos)
	queue_redraw()

## The angle the wood is drawn from: the grid's view orientation, so rotating
## the course turns every tree with it, exactly as it turns the buildings.
func view_facing() -> int:
	return terrain_grid.get_view_orientation() if terrain_grid else DEFAULT_FACING

# =============================================================================
# ART LOOKUP — the toolbar's tree tiles read their preview from here too
# =============================================================================

## The species growing on a tile: the tile's own for a species tile, or one of
## the theme's for the generic Trees ground. Deterministic per position.
static func species_at(type: int, pos: Vector2i) -> String:
	var species := TerrainTypes.get_tree_species(type)
	if not species.is_empty():
		return species
	var theme: int = GameManager.current_theme if GameManager else CourseTheme.Type.PARKLAND
	var theme_trees: Array = CourseTheme.get_tree_types(theme)
	if theme_trees.is_empty():
		return "oak"
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed(pos)
	return TerrainTypes.get_tree_species(theme_trees[rng.randi_range(0, theme_trees.size() - 1)])

## The file suffix of the angle at view orientation `facing` ("n", "e", "s"
## or "w"). Orientations outside 0..3 wrap, as the view itself does.
static func facing_name(facing: int) -> String:
	return FACINGS[wrapi(facing, 0, FACINGS.size())]

## The sprite a species wears right now, seen from view orientation `facing`,
## or "" when it has no art and the tile falls back to its silhouette. The
## angled view of the season's art is preferred; the authored (unsuffixed)
## drawing answers for a view that has not been generated, so a species with
## only its north drawing still stands from every angle.
static func sprite_path(species: String, day: int = -1, theme: int = -1,
		facing: int = DEFAULT_FACING) -> String:
	var which_day: int = day if day >= 0 else (GameManager.current_day if GameManager else 1)
	var which_theme: int = theme if theme >= 0 \
			else (GameManager.current_theme if GameManager else CourseTheme.Type.PARKLAND)
	var season_name: String = SeasonSystem.get_season_name(SeasonSystem.get_season(which_day)).to_lower()
	# The art to look for, most seasonal first: the right season at the
	# authored angle outranks the wrong season at the right one.
	var stems: Array[String] = []
	if species in DECIDUOUS_SPECIES and season_name != "summer":
		stems.append("%s/%s" % [season_name, species])
	# A pine holds snow where winters are cold enough for it to matter.
	if species == "pine" and season_name == "winter" and which_theme in SNOWY_THEMES:
		stems.append("winter/pine")
	stems.append(species)
	for stem in stems:
		var angled := "%s%s_%s.png" % [SPRITE_DIR, stem, facing_name(facing)]
		if ResourceLoader.exists(angled):
			return angled
		var authored := "%s%s.png" % [SPRITE_DIR, stem]
		if ResourceLoader.exists(authored):
			return authored
	return ""

## The loaded texture for a species at one angle, cached by path. A missing
## file is remembered as null so it is looked up once, not on every tile of
## every redraw.
static func texture_for(species: String, facing: int = DEFAULT_FACING) -> Texture2D:
	var path := sprite_path(species, -1, -1, facing)
	if path.is_empty():
		return null
	if not _texture_cache.has(path):
		_texture_cache[path] = load(path) as Texture2D
	return _texture_cache[path]

## How far above a sprite's centre its trunk meets the tile, scaled to `size`.
static func base_offset(species: String, size: Vector2) -> float:
	return float(SPRITE_BASE_OFFSETS.get(species, size.y * 0.5))

## The one RNG seed per tile, shared by the species pick and the tree's own
## variation, so the course reads the same on every machine and every reload.
static func variation_seed(pos: Vector2i) -> int:
	return pos.x * 31337 ^ pos.y * 65537

# =============================================================================
# DRAWING
# =============================================================================

func _on_load_completed(_success: bool) -> void:
	rescan()

func _on_season_changed(_old_season: int, _new_season: int) -> void:
	queue_redraw()  # The art lookup follows the calendar; the tiles do not move.

func _on_theme_changed(_theme: int) -> void:
	rescan()  # Only the generic Trees tiles pick their species from the theme.

func _on_view_rotated(_orientation: int, _isometric: bool) -> void:
	queue_redraw()  # The art lookup follows the view; the tiles do not move.

func _on_terrain_tile_changed(tile_pos: Vector2i, old_type: int, new_type: int) -> void:
	if TerrainTypes.is_tree(new_type):
		_tree_tiles[tile_pos] = species_at(new_type, tile_pos)
	elif TerrainTypes.is_tree(old_type):
		_tree_tiles.erase(tile_pos)
	else:
		return  # Something else was painted here; the wood is unchanged.
	queue_redraw()

func _draw() -> void:
	if not terrain_grid or _tree_tiles.is_empty():
		return
	# Crowns rise well above their tile, so cull with room above each tile.
	var margin_x := float(terrain_grid.tile_width) * 2.0
	var margin_y := float(terrain_grid.tile_height) * 4.0
	var view: Rect2 = terrain_grid.get_visible_world_rect() \
			.grow_individual(margin_x, margin_y, margin_x, margin_y)
	var grounds: Dictionary = {}
	var ordered: Array = []
	for pos in _tree_tiles:
		var ground: Vector2 = terrain_grid.grid_to_screen_center(pos)
		if view.has_point(ground):
			grounds[pos] = ground
			ordered.append(pos)
	# Back to front, so each tree belongs behind the wood in front of it.
	ordered.sort_custom(func(a, b): return grounds[a].y < grounds[b].y)
	var facing := view_facing()
	for pos in ordered:
		_draw_tree(pos, grounds[pos], facing)

## One tree: the contact shadow, then the species' sprite from the angle the
## course is viewed at — or its silhouette, turned the same way, when the
## art is missing.
func _draw_tree(pos: Vector2i, ground: Vector2, facing: int = DEFAULT_FACING) -> void:
	var species: String = _tree_tiles[pos]
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed(pos)
	var center := ground + Vector2(rng.randf_range(-JITTER_X, JITTER_X),
			rng.randf_range(-JITTER_Y, JITTER_Y))
	var scale_v := rng.randf_range(SCALE_MIN, SCALE_MAX)

	# A squat ellipse on the ground: the same flattened-circle trick the flower
	# bed uses for its foliage, so the tree reads as standing on the turf.
	var spread := terrain_grid.tile_width * 0.3 * scale_v
	draw_set_transform(ground, 0.0, Vector2(1.0, 0.5))
	draw_circle(Vector2(terrain_grid.tile_width * 0.06, terrain_grid.tile_height * 0.06),
			spread, Color(0, 0, 0, 0.2))
	draw_set_transform(Vector2.ZERO)

	var texture := texture_for(species, facing)
	if texture != null:
		var size := texture.get_size() * scale_v
		var top_left := center - Vector2(size.x * 0.5, size.y * 0.5 + base_offset(species, size))
		draw_texture_rect(texture, Rect2(top_left, size), false)
	else:
		_draw_silhouette(center, species, scale_v, facing)

## Fallback art: a trunk and a crown in the species' color, sized by its shape,
## so an evergreen, a shrub and a clump of grass still tell each other apart.
## It turns with the view like the generated views do (see PROFILES in
## tools/tree_art/generate.py): the back angles mirror it, the side angles
## foreshorten and lean it about its ground point, and the south angle is
## the side away from the sun, so it sits darker.
func _draw_silhouette(center: Vector2, species: String, scale_v: float,
		facing: int = DEFAULT_FACING) -> void:
	var turned := wrapi(facing, 0, FACINGS.size())
	var foliage := TerrainTypes.get_color(TerrainTypes.tree_tile_for_species(species))
	var trunk := Color(0.45, 0.32, 0.2)
	if turned == 2:
		foliage = foliage.darkened(0.12)
		trunk = trunk.darkened(0.12)
	var mirror := -1.0 if turned >= 2 else 1.0
	var profile := 0.82 if turned == 1 or turned == 3 else 1.0
	var tilt := 0.0
	if turned == 1:
		tilt = 0.05
	elif turned == 3:
		tilt = -0.05
	draw_set_transform(center, tilt, Vector2(mirror * profile, 1.0))
	center = Vector2.ZERO  # Everything below is measured from the ground point.
	var shape := str(CANOPY_SHAPES.get(species, "broadleaf"))
	match shape:
		"conifer":
			_trunk(center, 3.0 * scale_v, 12.0 * scale_v, trunk)
			for tier in 3:
				var width := (28.0 - tier * 7.0) * scale_v
				var bottom := center.y - (10.0 + tier * 10.0) * scale_v
				draw_colored_polygon(PackedVector2Array([
					Vector2(center.x - width * 0.5, bottom),
					Vector2(center.x + width * 0.5, bottom),
					Vector2(center.x, bottom - 16.0 * scale_v),
				]), foliage.lightened(tier * 0.05))
		"mound":
			_draw_foliage_blob(center + Vector2(0.0, -6.0 * scale_v), 12.0 * scale_v, foliage)
		"tuft":
			for blade in 5:
				var lean := (blade - 2) * 4.0 * scale_v
				draw_line(center + Vector2(lean * 0.4, 4.0 * scale_v),
						center + Vector2(lean, -16.0 * scale_v), foliage, 1.5)
		"reed":
			for stem in 4:
				var x := (stem - 1.5) * 5.0 * scale_v
				draw_line(center + Vector2(x, 4.0 * scale_v),
						center + Vector2(x, -20.0 * scale_v), foliage, 1.5)
				if stem % 2 == 0:
					draw_rect(Rect2(center + Vector2(x - 1.6 * scale_v, -27.0 * scale_v),
							Vector2(3.2 * scale_v, 7.0 * scale_v)), Color(0.45, 0.3, 0.15))
		"column":
			draw_rect(Rect2(center + Vector2(-4.0 * scale_v, -34.0 * scale_v),
					Vector2(8.0 * scale_v, 38.0 * scale_v)), foliage)
			draw_rect(Rect2(center + Vector2(-14.0 * scale_v, -26.0 * scale_v),
					Vector2(10.0 * scale_v, 4.0 * scale_v)), foliage)
			draw_rect(Rect2(center + Vector2(4.0 * scale_v, -20.0 * scale_v),
					Vector2(10.0 * scale_v, 4.0 * scale_v)), foliage)
		"bare":
			_trunk(center, 4.0 * scale_v, 26.0 * scale_v, trunk)
			for side in [-1.0, 1.0]:
				draw_line(center + Vector2(0.0, -18.0 * scale_v),
						center + Vector2(side * 14.0 * scale_v, -34.0 * scale_v), trunk, 2.5)
		"fan":
			_trunk(center, 3.5 * scale_v, 34.0 * scale_v, trunk)
			for frond in 6:
				var angle := frond * TAU / 6.0
				draw_line(center + Vector2(0.0, -34.0 * scale_v),
						center + Vector2(cos(angle), sin(angle) * 0.6) * 20.0 * scale_v,
						foliage, 3.0)
		_:
			_trunk(center, 4.0 * scale_v, 16.0 * scale_v, trunk)
			_draw_foliage_blob(center + Vector2(0.0, -24.0 * scale_v), 20.0 * scale_v, foliage)
			_draw_foliage_blob(center + Vector2(-9.0 * scale_v, -18.0 * scale_v),
					13.0 * scale_v, foliage.lightened(0.06))
			_draw_foliage_blob(center + Vector2(9.0 * scale_v, -19.0 * scale_v),
					12.0 * scale_v, foliage.darkened(0.06))
	draw_set_transform(Vector2.ZERO)

func _trunk(base: Vector2, half_width: float, height: float, color: Color) -> void:
	draw_rect(Rect2(base + Vector2(-half_width, -height), Vector2(half_width * 2.0, height)), color)

## An irregular blob, so a crown is roundish rather than a drawn circle.
func _draw_foliage_blob(center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle := i * TAU / 8.0
		var r := radius * (0.85 + 0.15 * sin(angle * 3.0))
		points.append(center + Vector2(cos(angle), sin(angle) * 0.85) * r)
	draw_colored_polygon(points, color)
