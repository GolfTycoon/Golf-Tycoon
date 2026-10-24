extends Node2D
class_name TreeOverlay
## TreeOverlay - draws the standing trees that grow on every woodland tile
##
## Woodland is painted, not planted. A Pine Tree tile is one terrain id, laid
## and replaced like Rocks or Wild Flowers, so there is no tree to place, to
## own, to clear or to undo: the tile is the tree. The course surface keeps the
## turf a grove shares with its neighbours (see `tile_at()` in
## `course_surface.gdshader`) and this overlay paints the canopies over it —
## one independently depth-sorted CanvasItem per standing tree.
##
## A tile's species is its own terrain id's; the generic `Type.TREES` tile —
## the ground older saves carry, and what the generators paint when they want a
## wood rather than a plantation — picks from the course theme's species, seeded
## from the tile's coordinates so the mix is varied yet identical every time the
## course loads.
##
## Each species can have four independently authored angles —
## `<species>_n.png`, `_e`, `_s` and `_w` — and the overlay paints the matching
## view as the course turns (see BuildingSprites). Views may have different
## canvas dimensions: `layout.json` supplies their scale and normalized ground
## anchor, while the renderer positions each texture from its own size. If a
## view is missing, the unsuffixed drawing or north view is used as a fallback.
##
## A season's drawings of a species are not the core's to ship: the spring,
## fall and winter art travels inside the mod that provides the calendar —
## `mods/golf_tycoon.seasons/tree_art/<season>/` — and reaches this lookup
## through its manifest's `tree_art_root` (see `register_mod_art()`). With
## that mod switched off the year never leaves summer, so the evergreen art in
## `SPRITE_DIR` is all a tree ever wears and nothing misses the wardrobe.
##
## A mod may also put `<species>[_n|_e|_s|_w].png` straight in that
## `tree_art_root`. Those are all-season sprite replacements: they are checked
## before both the seasonal wardrobe and the core art, so a sprite pack can
## repaint every tree without having to duplicate its files into four seasons.
##
## A tree does not wear the view the course is seen from, though: each tile has
## its own quarter-turn offset (see `facing_offset()`), fixed for the life of
## the course, so a wood is drawn with canopies from all four sides at once
## instead of a plantation whose every tree faces the camera. The offset is
## added to the course's view orientation, so rotating the course still steps
## every tree on to its next angle — one turn of the screen turns the whole
## wood, and a tree is never seen twice from the same side in a row.

## The evergreen art lives here as `<species>_n/_e/_s/_w.png`; each facing is
## an independent source image, so its canvas can be sized to suit that view.
## `layout.json` next to these files controls draw scale and the ground anchor.
## This is the summer art of every species, and the only tree art the game
## itself ships — a season's variants come from the mods (see
## `register_mod_art()`).
const SPRITE_DIR := "res://assets/sprites/trees/"

## The image files a registered art folder is scanned for: what
## ModManager.load_mod_texture can decode, PNG — the art pipeline's output —
## first among them.
const ART_EXTENSIONS: Array[String] = ["png", "jpg", "jpeg", "webp", "bmp"]

## A JSON sidecar used by the bundled sprites and optional in a mod's declared
## tree-art folder. It adjusts draw scale and ground point without baking a new
## canvas into every PNG; see docs/modding/manifest-and-packaging.md.
const ART_LAYOUT_FILE := "layout.json"
const MIN_ART_SCALE := 0.05
const MAX_ART_SCALE := 4.0

## The four angles a tree is drawn from, indexed by view orientation (see
## TerrainGrid.get_view_orientation()): 0 is the course compass's north — the
## default view, whose art is the authored drawing — then a quarter turn
## clockwise per step through east and south to west.
const FACINGS: Array[String] = ["n", "e", "s", "w"]

## The angle drawn when nothing names one: the authored north view. It is
## what the toolbar's tree tiles preview, so a button never turns with the
## course behind it.
const DEFAULT_FACING := 0

## Themes cold enough for snow to lie on a pine through winter. The rest of a
## pine's wardrobe — which seasons it has one at all — is whatever art the
## loaded mods registered for it.
const SNOWY_THEMES: Array[int] = [
	CourseTheme.Type.PARKLAND, CourseTheme.Type.MOUNTAIN, CourseTheme.Type.HEATHLAND,
]

## Legacy ground offsets for art without a layout entry (including older
## seasonal/mod sprites). New asset folders should provide `layout.json` with a
## normalized ground anchor so changing image dimensions needs no code edit.
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
var _visuals: Dictionary = {}
var _tree_tiles: Dictionary = {}  # Vector2i -> species key drawn on that tile

static var _texture_cache: Dictionary = {}  # sprite path -> Texture2D (or null)
## Per-file layout supplied by a mod's optional `tree_art/layout.json`.
## Changes are draw-time only; source images remain lossless and replaceable.
static var _art_layouts: Dictionary = {}  # mod sprite path -> Dictionary
## The bundled art has the same layout format in `SPRITE_DIR/layout.json`.
## Resolve and cache each file's merged settings separately from mod layouts,
## which can be unloaded and replaced while the game is running.
static var _core_layout_data: Dictionary = {}
static var _core_layout_cache: Dictionary = {}  # sprite path -> Dictionary
static var _core_layout_loaded := false

## An all-season replacement's art, registered from the files directly inside
## a mod's `tree_art_root`: species -> facing suffix ("" for an authored
## drawing, then "_n", "_e", "_s", "_w") -> file. This is deliberately a
## different shelf from the seasonal wardrobe below: it is the first lookup so
## a sprite-replacement pack keeps its promise across every day of the year.
static var _sprite_overrides: Dictionary = {}
## Which mod supplied each all-season replacement file, so a user-library or
## Workshop copy can be decoded from its source bytes.
static var _sprite_override_owners: Dictionary = {}  # file path -> mod id

## A season's tree art, registered by the mods that ship it: season folder name
## ("spring") -> species -> facing suffix ("" for the authored drawing, then
## "_n", "_e", "_s", "_w") -> the file to draw. Filled from the `tree_art_root`
## content key by ContentRegistry, in load order, and dropped with the rest of
## a mod's content — so a game with the Seasons mod off holds no seasonal art,
## and never asks for any.
static var _season_art: Dictionary = {}
## Which mod shipped each registered seasonal file, so art from outside the
## imported project — an installed or Workshop copy — is decoded by the loader
## that knows how.
static var _season_art_owners: Dictionary = {}  # file path -> mod id

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	# Trees share the entity band and the world Y-sort, not the ground band.
	z_index = 2
	y_sort_enabled = true
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

## The angle the course is viewed from: the grid's view orientation, so
## rotating the course turns every tree with it, exactly as it turns the
## buildings. A tree is drawn from `facing_at()` — this angle plus the tile's
## own offset — so trees in the same wood face different ways.
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

## The angle the tree on `pos` is drawn from when the course is viewed at
## orientation `view`: the course's own angle, stepped by the tile's offset.
## Everything turns together, so a quarter turn of the course always takes
## every tree on to its next view and a full turn brings the wood back exactly
## as it was.
static func facing_at(pos: Vector2i, view: int = DEFAULT_FACING) -> int:
	return wrapi(view + facing_offset(pos), 0, FACINGS.size())

## How many quarter turns this tile's tree stands turned from the authored
## north drawing: 0..3, one per tile, the same on every machine and every
## reload. It is what lets one screen hold a wood of mixed angles rather than
## a row of trees all facing the camera: about a quarter of the trees keep the
## authored drawing, and the rest show their east, south or west side.
static func facing_offset(pos: Vector2i) -> int:
	# A mixed hash rather than a cheap `x + y`: a linear seed sorts a wood into
	# diagonal stripes of identically turned trees, which reads as a pattern
	# instead of a plantation. (Deliberately not `variation_seed()`, so the
	# angle a tree stands at is independent of the height and lean jitter it
	# also draws from that seed.)
	var hash_value := (pos.x * 0x1f1f1f1f + pos.y * 0x27d4eb2d) & 0x7FFFFFFF
	hash_value = ((hash_value ^ (hash_value >> 15)) * 0x85ebca6b) & 0x7FFFFFFF
	hash_value = (hash_value ^ (hash_value >> 13)) * 0xc2b2ae35
	hash_value = (hash_value ^ (hash_value >> 16)) & 0x7FFFFFFF
	return hash_value % FACINGS.size()

## The sprite a species wears right now, seen from view orientation `facing`,
## or "" when it has no art and the tile falls back to its silhouette. A
## dedicated facing is preferred; an unsuffixed drawing, then the north view,
## fills any angle that has not been supplied.
static func sprite_path(species: String, day: int = -1, theme: int = -1,
		facing: int = DEFAULT_FACING) -> String:
	# A flat file inside a mod's tree_art_root means "replace this sprite", not
	# "give it one more season". Check that shelf before the calendar so one
	# cosmetic pack can cover the whole year, including a pine in mild weather.
	var replacement := sprite_override_file(species, facing)
	if not replacement.is_empty():
		return replacement
	var which_day: int = day if day >= 0 else (GameManager.current_day if GameManager else 1)
	var which_theme: int = theme if theme >= 0 \
		else (GameManager.current_theme if GameManager else CourseTheme.Type.PARKLAND)
	var season_name: String = SeasonSystem.get_season_name(SeasonSystem.get_season(which_day)).to_lower()
	# The art to look for, most seasonal first: the right season at the
	# authored angle outranks the wrong season at the right one.
	var stems: Array[String] = []
	if wears_season_art(species, season_name, which_theme):
		stems.append("%s/%s" % [season_name, species])
	stems.append(species)
	for stem in stems:
		var found := art_file(stem, facing)
		if not found.is_empty():
			return found
	return ""

## Whether a species asks its season for art at all. Which art a season has is
## the season mod's declaration (`register_mod_art()`), and a species with none
## simply keeps wearing its evergreen drawing — this is the one rule the core
## holds on to: a pine wears snow only where the theme's winters are cold
## enough for it to lie, and stays green in a desert however white the year.
static func wears_season_art(species: String, season_name: String, theme: int) -> bool:
	if species != "pine":
		return true
	return season_name == "winter" and theme in SNOWY_THEMES

## The file an all-season sprite pack supplies for `species` at `facing`, or
## "" when no enabled mod replaces that particular view. An unsuffixed drawing
## fills missing angles; if the pack has only a north view, that can fill them too.
static func sprite_override_file(species: String, facing: int) -> String:
	var faces: Dictionary = _sprite_overrides.get(species, {})
	for suffix in ["_" + facing_name(facing), "", "_n"]:
		var registered: String = str(faces.get(suffix, ""))
		if not registered.is_empty():
			return registered
	return ""

## The file one art stem is drawn from at `facing`, or "" when there is none:
## the angled view first, then the unsuffixed drawing, then north. A stem
## carrying a season ("spring/oak") is looked up in the art the mods
## registered; a bare species is the core's own evergreen art.
static func art_file(stem: String, facing: int) -> String:
	var angle := "_" + facing_name(facing)
	var suffixes: Array[String] = [angle, "", "_n"]
	if not stem.contains("/"):
		for suffix in suffixes:
			var core_path: String = SPRITE_DIR + stem + suffix + ".png"
			if ResourceLoader.exists(core_path):
				return core_path
		return ""
	var per_species: Dictionary = _season_art.get(stem.get_slice("/", 0), {})
	var faces: Dictionary = per_species.get(stem.get_slice("/", 1), {})
	for suffix in suffixes:
		var registered: String = str(faces.get(suffix, ""))
		if not registered.is_empty():
			return registered
	return ""

## The loaded texture for a species at one angle, or null when it has no art
## and the tile is drawn as a silhouette.
static func texture_for(species: String, facing: int = DEFAULT_FACING) -> Texture2D:
	return texture_at(sprite_path(species, -1, -1, facing))

## The texture at a path this lookup returned, cached by path. A missing file
## is remembered as null so it is looked up once, not on every tile of every
## redraw.
static func texture_at(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _texture_cache.has(path):
		_texture_cache[path] = _load_art(path)
	return _texture_cache[path]

## One art file: the imported resource when the project has one (the bundled
## mods, and a checkout Godot has imported), else the file's own bytes decoded
## — a mod's art needs no import step, wherever it was installed from.
static func _load_art(path: String) -> Texture2D:
	if ResourceLoader.exists(path):
		return load(path) as Texture2D
	var owner_mod: String = str(_sprite_override_owners.get(path,
			_season_art_owners.get(path, "")))
	if owner_mod.is_empty() or ModManager == null:
		return null
	return ModManager.load_mod_texture(owner_mod, path)

# =============================================================================
# MOD TREE ART — seasonal wardrobes and all-season sprite replacements
# =============================================================================

## Add one mod's tree-art folder. Its root may hold all-season replacements
## (`<root>/<species>[_n|_e|_s|_w].png`) and its season folders may hold a
## wardrobe (`<root>/<season>/<species>[_n|_e|_s|_w].png`). A season is the
## lower-cased result of SeasonSystem.get_season_name(): spring, summer, fall
## or winter. An optional `<root>/layout.json` gives the images a draw scale and
## ground point without modifying those images. ContentRegistry calls this for
## every mod whose manifest declares `tree_art_root`, in load order. A later mod
## wins a repeated view on the same shelf; root-level art always beats seasonal
## art during lookup, by design. Returns how many image files were registered,
## so the loader can report an empty art folder to the player.
static func register_mod_art(mod_id: String, root: String) -> int:
	unregister_mod_art(mod_id)
	if not DirAccess.dir_exists_absolute(root):
		return 0
	var layout := _read_art_layout(root)
	var registered := _register_sprite_overrides(mod_id, root, layout)
	for season in DirAccess.get_directories_at(root):
		if season.begins_with("."):
			continue
		var season_dir := root.path_join(season)
		var per_species: Dictionary = _season_art.get(season, {})
		for file in DirAccess.get_files_at(season_dir):
			if not ART_EXTENSIONS.has(file.get_extension().to_lower()):
				continue
			var parts := _sprite_file_parts(file)
			var species: String = parts["species"]
			var suffix: String = parts["suffix"]
			var faces: Dictionary = per_species.get(species, {})
			var path := season_dir.path_join(file)
			var replaced: String = str(faces.get(suffix, ""))
			if not replaced.is_empty() and replaced != path:
				# A later mod in the load order wins this season's drawing.
				_season_art_owners.erase(replaced)
				_texture_cache.erase(replaced)
				_art_layouts.erase(replaced)
			faces[suffix] = path
			_season_art_owners[path] = mod_id
			_art_layouts[path] = _layout_for_sprite(parts, layout)
			per_species[species] = faces
			registered += 1
		if not per_species.is_empty():
			_season_art[season] = per_species
	return registered

## Register the direct files in a tree-art root as an all-season replacement
## shelf. This is private to register_mod_art() so both shelf types have one
## lifecycle: changing a mod cannot leave obsolete sprite files behind.
static func _register_sprite_overrides(mod_id: String, root: String, layout: Dictionary) -> int:
	var registered := 0
	for file in DirAccess.get_files_at(root):
		if not ART_EXTENSIONS.has(file.get_extension().to_lower()):
			continue
		var parts := _sprite_file_parts(file)
		var species: String = parts["species"]
		var suffix: String = parts["suffix"]
		var faces: Dictionary = _sprite_overrides.get(species, {})
		var path := root.path_join(file)
		var replaced: String = str(faces.get(suffix, ""))
		if not replaced.is_empty() and replaced != path:
			# A later mod in the load order wins this all-season view.
			_sprite_override_owners.erase(replaced)
			_texture_cache.erase(replaced)
			_art_layouts.erase(replaced)
		faces[suffix] = path
		_sprite_override_owners[path] = mod_id
		_art_layouts[path] = _layout_for_sprite(parts, layout)
		_sprite_overrides[species] = faces
		registered += 1
	return registered

## Split an art filename into the species key and optional facing suffix. The
## loader accepts an unsuffixed authored drawing as the fallback for every view.
static func _sprite_file_parts(file: String) -> Dictionary:
	var stem := file.get_basename()
	var species := stem
	var suffix := ""
	for facing in FACINGS:
		if stem.length() > facing.length() + 1 and stem.ends_with("_" + facing):
			species = stem.substr(0, stem.length() - facing.length() - 1)
			suffix = "_" + facing
			break
	return {"species": species, "suffix": suffix}

## Read an art-layout sidecar once per root. It can set `scale`, source-pixel
## anchors (`ground_x`, `ground_y`), normalized anchors (`ground_x_ratio`,
## `ground_y_ratio`) and post-scale nudges (`offset_x`, `offset_y`). Root values
## apply to every file, species values override them, then an exact
## `<species>_<facing>` entry wins. Invalid fields are ignored so a bad tune
## never hides the art.
static func _read_art_layout(root: String) -> Dictionary:
	var result: Dictionary = {"default": {}, "species": {}, "sprites": {}}
	var path := root.path_join(ART_LAYOUT_FILE)
	if not FileAccess.file_exists(path):
		return result
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return result
	var raw: Dictionary = json.data
	result["default"] = _layout_values(raw)
	result["species"] = _layout_entries(raw.get("species", {}))
	result["sprites"] = _layout_entries(raw.get("sprites", {}))
	return result

## Pick the layout values that apply to one filename, from broadest to most
## specific. Copies keep one file's style from being mutated by another's.
static func _layout_for_sprite(parts: Dictionary, layout: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	var default_values: Variant = layout.get("default", {})
	if default_values is Dictionary:
		result = default_values.duplicate()
	var species := str(parts.get("species", ""))
	var species_layouts: Dictionary = layout.get("species", {})
	var species_values: Variant = species_layouts.get(species, {})
	if species_values is Dictionary:
		result.merge(species_values, true)
	var sprite_name := species + str(parts.get("suffix", ""))
	var sprite_layouts: Dictionary = layout.get("sprites", {})
	var sprite_values: Variant = sprite_layouts.get(sprite_name, {})
	if sprite_values is Dictionary:
		result.merge(sprite_values, true)
	return result

## The usable numeric fields from one layout entry. Scale is clamped to avoid
## a typo making a zero-sized sprite or swallowing the whole course.
static func _layout_values(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (raw is Dictionary):
		return result
	var scale_value: Variant = raw.get("scale", null)
	if scale_value is int or scale_value is float:
		result["scale"] = clampf(float(scale_value), MIN_ART_SCALE, MAX_ART_SCALE)
	for field in ["ground_x", "ground_y", "offset_x", "offset_y"]:
		var value: Variant = raw.get(field, null)
		if value is int or value is float:
			result[field] = float(value)
	for field in ["ground_x_ratio", "ground_y_ratio"]:
		var ratio: Variant = raw.get(field, null)
		if ratio is int or ratio is float:
			result[field] = clampf(float(ratio), 0.0, 1.0)
	return result

## The map form of `species` and `sprites`: only entries with a usable layout
## field survive, so a misspelled key harmlessly falls back to the broader rule.
static func _layout_entries(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (raw is Dictionary):
		return result
	for key in raw:
		var values := _layout_values(raw[key])
		if not values.is_empty():
			result[str(key)] = values
	return result

## Resolve the layout for one file. Core art reads the shared layout sidecar;
## registered mod art already has its merged layout cached per source file.
static func _layout_for_path(path: String) -> Dictionary:
	if _art_layouts.has(path):
		return _art_layouts[path]
	if not path.begins_with(SPRITE_DIR):
		return {}
	if _core_layout_cache.has(path):
		return _core_layout_cache[path]
	if not _core_layout_loaded:
		_core_layout_data = _read_art_layout(SPRITE_DIR)
		_core_layout_loaded = true
	var parts := _sprite_file_parts(path.get_file())
	var layout := _layout_for_sprite(parts, _core_layout_data)
	_core_layout_cache[path] = layout
	return layout

## The scale a loaded art file is drawn at. Layout values can differ by root,
## species or facing; an image without a layout remains at native size.
static func art_scale(path: String) -> float:
	var layout := _layout_for_path(path)
	return clampf(float(layout.get("scale", 1.0)), MIN_ART_SCALE, MAX_ART_SCALE)

## Final placement nudges in rendered pixels. These are applied after scaling,
## so an artist can compare them directly with the course tile.
static func art_offset_x(path: String) -> float:
	var layout := _layout_for_path(path)
	return float(layout.get("offset_x", 0.0))

static func art_offset_y(path: String) -> float:
	var layout := _layout_for_path(path)
	return float(layout.get("offset_y", 0.0))

## The vertical offset from an image's centre to its terrain point. Exact
## `ground_y` uses source pixels; `ground_y_ratio` follows a canvas that changes
## size; older layouts without either field use the legacy species offset.
static func art_base_offset(species: String, path: String, source_size: Vector2,
		variation_scale: float = 1.0) -> float:
	var layout := _layout_for_path(path)
	var art_scale_value := art_scale(path)
	if layout.has("ground_y") or layout.has("ground_y_ratio"):
		var ground_y := float(layout.get("ground_y",
				source_size.y * float(layout.get("ground_y_ratio", 0.5))))
		return (ground_y - source_size.y * 0.5) * art_scale_value * variation_scale
	return base_offset(species, source_size, art_scale_value * variation_scale)

## The 2D offset from the image's centre to its terrain anchor. Ratios are
## useful when facing sprites have different dimensions: one layout setting
## stays correct when the PNG is replaced with another canvas size.
static func art_anchor_offset(species: String, path: String, source_size: Vector2,
		variation_scale: float = 1.0) -> Vector2:
	var layout := _layout_for_path(path)
	var anchor_x := 0.0
	if layout.has("ground_x") or layout.has("ground_x_ratio"):
		var ground_x := float(layout.get("ground_x",
				source_size.x * float(layout.get("ground_x_ratio", 0.5))))
		anchor_x = (ground_x - source_size.x * 0.5) * art_scale(path) * variation_scale
	return Vector2(anchor_x, art_base_offset(species, path, source_size, variation_scale))

## Drop one mod's art, and the textures loaded from it: the loader calls it
## before a mod set is re-applied, and `register_mod_art()` calls it so a mod
## registering twice replaces its art rather than stacking over it.
static func unregister_mod_art(mod_id: String) -> void:
	for override_species in _sprite_overrides.keys():
		var override_faces: Dictionary = _sprite_overrides[override_species]
		for override_suffix in override_faces.keys():
			var override_path: String = str(override_faces[override_suffix])
			if str(_sprite_override_owners.get(override_path, "")) != mod_id:
				continue
			_sprite_override_owners.erase(override_path)
			_texture_cache.erase(override_path)
			_art_layouts.erase(override_path)
			override_faces.erase(override_suffix)
		if override_faces.is_empty():
			_sprite_overrides.erase(override_species)
	for season in _season_art.keys():
		var per_species: Dictionary = _season_art[season]
		for seasonal_species in per_species.keys():
			var seasonal_faces: Dictionary = per_species[seasonal_species]
			for seasonal_suffix in seasonal_faces.keys():
				var seasonal_path: String = str(seasonal_faces[seasonal_suffix])
				if str(_season_art_owners.get(seasonal_path, "")) != mod_id:
					continue
				_season_art_owners.erase(seasonal_path)
				_texture_cache.erase(seasonal_path)
				_art_layouts.erase(seasonal_path)
				seasonal_faces.erase(seasonal_suffix)
			if seasonal_faces.is_empty():
				per_species.erase(seasonal_species)
		if per_species.is_empty():
			_season_art.erase(season)

## Forget every mod's art, and the textures loaded from it — what
## ContentRegistry.reset_mod_content() does when the mod set is re-run or the
## last mod is switched off.
static func clear_mod_art() -> void:
	_sprite_overrides.clear()
	_sprite_override_owners.clear()
	_season_art.clear()
	_season_art_owners.clear()
	_art_layouts.clear()
	_texture_cache.clear()

## How far above a sprite's centre its trunk meets the tile. `scale_factor`
## keeps a downsized or enlarged mod sprite anchored proportionally to its art.
static func base_offset(species: String, size: Vector2, scale_factor: float = 1.0) -> float:
	return float(SPRITE_BASE_OFFSETS.get(species, size.y * 0.5)) * scale_factor

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
	_sync_visuals()

func _sync_visuals() -> void:
	for pos in _visuals.keys():
		if not _tree_tiles.has(pos):
			var obsolete: Node2D = _visuals[pos]
			remove_child(obsolete)
			obsolete.queue_free()
			_visuals.erase(pos)
	for pos in _tree_tiles:
		if not _visuals.has(pos):
			var tree := Node2D.new()
			tree.draw.connect(func(): _draw_tree(tree, pos, Vector2.ZERO, facing_for(pos)))
			add_child(tree)
			_visuals[pos] = tree
		var visual: Node2D = _visuals[pos]
		visual.position = terrain_grid.grid_to_screen_center(pos)
		visual.queue_redraw()

## The angle this overlay paints the tree on `pos` from right now: the course's
## view turned by the tile's own offset, so a wood holds several angles at once
## and a rotation steps them all on together.
func facing_for(pos: Vector2i) -> int:
	return facing_at(pos, view_facing())

## One tree: the species' sprite from this tree's own angle at the current view
## — or its silhouette, turned the same way, when the art is missing. The
## sprite is drawn straight onto the turf its tile paints: a contact shadow
## under it only muddied the ground art the tree already sits in.
func _draw_tree(canvas: Node2D, pos: Vector2i, ground: Vector2, facing: int = DEFAULT_FACING) -> void:
	var species: String = _tree_tiles[pos]
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed(pos)
	var center := ground + Vector2(rng.randf_range(-JITTER_X, JITTER_X),
			rng.randf_range(-JITTER_Y, JITTER_Y))
	var scale_v := rng.randf_range(SCALE_MIN, SCALE_MAX)

	var path := sprite_path(species, -1, -1, facing)
	var texture := texture_at(path)
	if texture != null:
		var source_size := texture.get_size()
		var size := source_size * scale_v * art_scale(path)
		var anchor := art_anchor_offset(species, path, source_size, scale_v)
		var top_left := center - size * 0.5 - anchor
		top_left += Vector2(art_offset_x(path), art_offset_y(path))
		canvas.draw_texture_rect(texture, Rect2(top_left, size), false)
	else:
		_draw_silhouette(canvas, center, species, scale_v, facing)

## Fallback art: a trunk and a crown in the species' color, sized by its shape,
## so an evergreen, a shrub and a clump of grass still tell each other apart.
## It turns with its tree's angle like the generated views do (see PROFILES in
## tools/tree_art/generate.py): the back angles mirror it, the side angles
## foreshorten and lean it about its ground point, and the south angle is
## the side away from the sun, so it sits darker.
func _draw_silhouette(canvas: Node2D, center: Vector2, species: String, scale_v: float,
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
	canvas.draw_set_transform(center, tilt, Vector2(mirror * profile, 1.0))
	center = Vector2.ZERO  # Everything below is measured from the ground point.
	var shape := str(CANOPY_SHAPES.get(species, "broadleaf"))
	match shape:
		"conifer":
			_trunk(canvas, center, 3.0 * scale_v, 12.0 * scale_v, trunk)
			for tier in 3:
				var width := (28.0 - tier * 7.0) * scale_v
				var bottom := center.y - (10.0 + tier * 10.0) * scale_v
				canvas.draw_colored_polygon(PackedVector2Array([
					Vector2(center.x - width * 0.5, bottom),
					Vector2(center.x + width * 0.5, bottom),
					Vector2(center.x, bottom - 16.0 * scale_v),
				]), foliage.lightened(tier * 0.05))
		"mound":
			_draw_foliage_blob(canvas, center + Vector2(0.0, -6.0 * scale_v), 12.0 * scale_v, foliage)
		"tuft":
			for blade in 5:
				var lean := (blade - 2) * 4.0 * scale_v
				canvas.draw_line(center + Vector2(lean * 0.4, 4.0 * scale_v),
						center + Vector2(lean, -16.0 * scale_v), foliage, 1.5)
		"reed":
			for stem in 4:
				var x := (stem - 1.5) * 5.0 * scale_v
				canvas.draw_line(center + Vector2(x, 4.0 * scale_v),
						center + Vector2(x, -20.0 * scale_v), foliage, 1.5)
				if stem % 2 == 0:
					canvas.draw_rect(Rect2(center + Vector2(x - 1.6 * scale_v, -27.0 * scale_v),
							Vector2(3.2 * scale_v, 7.0 * scale_v)), Color(0.45, 0.3, 0.15))
		"column":
			canvas.draw_rect(Rect2(center + Vector2(-4.0 * scale_v, -34.0 * scale_v),
					Vector2(8.0 * scale_v, 38.0 * scale_v)), foliage)
			canvas.draw_rect(Rect2(center + Vector2(-14.0 * scale_v, -26.0 * scale_v),
					Vector2(10.0 * scale_v, 4.0 * scale_v)), foliage)
			canvas.draw_rect(Rect2(center + Vector2(4.0 * scale_v, -20.0 * scale_v),
					Vector2(10.0 * scale_v, 4.0 * scale_v)), foliage)
		"bare":
			_trunk(canvas, center, 4.0 * scale_v, 26.0 * scale_v, trunk)
			for side in [-1.0, 1.0]:
				canvas.draw_line(center + Vector2(0.0, -18.0 * scale_v),
						center + Vector2(side * 14.0 * scale_v, -34.0 * scale_v), trunk, 2.5)
		"fan":
			_trunk(canvas, center, 3.5 * scale_v, 34.0 * scale_v, trunk)
			for frond in 6:
				var angle := frond * TAU / 6.0
				canvas.draw_line(center + Vector2(0.0, -34.0 * scale_v),
						center + Vector2(cos(angle), sin(angle) * 0.6) * 20.0 * scale_v,
						foliage, 3.0)
		_:
			_trunk(canvas, center, 4.0 * scale_v, 16.0 * scale_v, trunk)
			_draw_foliage_blob(canvas, center + Vector2(0.0, -24.0 * scale_v), 20.0 * scale_v, foliage)
			_draw_foliage_blob(canvas, center + Vector2(-9.0 * scale_v, -18.0 * scale_v),
					13.0 * scale_v, foliage.lightened(0.06))
			_draw_foliage_blob(canvas, center + Vector2(9.0 * scale_v, -19.0 * scale_v),
					12.0 * scale_v, foliage.darkened(0.06))
	canvas.draw_set_transform(Vector2.ZERO)

func _trunk(canvas: Node2D, base: Vector2, half_width: float, height: float, color: Color) -> void:
	canvas.draw_rect(Rect2(base + Vector2(-half_width, -height), Vector2(half_width * 2.0, height)), color)

## An irregular blob, so a crown is roundish rather than a drawn circle.
func _draw_foliage_blob(canvas: Node2D, center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle := i * TAU / 8.0
		var r := radius * (0.85 + 0.15 * sin(angle * 3.0))
		points.append(center + Vector2(cos(angle), sin(angle) * 0.85) * r)
	canvas.draw_colored_polygon(points, color)
