extends Node2D
class_name TerrainFeatureOverlay
## TerrainFeatureOverlay - draws the sprite art of Brush, Rocks and Boulder tiles
##
## Three Course Terrain tiles are objects rather than patterns: **Brush** is a
## tangled stand of gorse, **Rocks** a slate outcrop, **Boulder** a rounded
## granite boulder.  Each is one painted terrain id, laid and replaced like a tree
## tile, and the course surface paints the ground beneath it (see `tile_at()` in
## `course_surface.gdshader`).  This overlay stands the sprite on that ground,
## one CanvasItem per drawing, the same arrangement `TreeOverlay` gives a
## canopy: each stone or bush Y-sorts and clips against the terrain on its own.
##
## The art lives in `assets/sprites/terrain/` as `<feature>_<variant>.png`, with
## up to four independently drawn variants per feature. A stable tile hash
## chooses each tile's drawing and it remains the same through view turns; only
## the tile-local scatter positions rotate to stay aligned with the terrain.
##
## Rocks and Brush are scatters rather than single objects: each of their tiles
## wears two or three *different* variant drawings, spread across the tile
## (`stamps_for()`).  Boulder is one mass and keeps to a single drawing.
##
## Unlike a tree, a feature is anchored to its *tile centre* rather than to a
## trunk's foot, and the point differs per drawing because the canvas was cropped
## to the outcrop's own silhouette.  `layout.json` beside the PNGs records the
## normalized `ground_x_ratio` / `ground_y_ratio` for every file, plus a draw
## scale, so the renderer positions each texture from its own size and a redrawn
## outcrop needs no code edit.
##
## The art is baked by `tools/terrain_art/generate.py` from the 3D models in
## `tools/terrain_art/features.py`, through the same isometric renderer, sun and
## quantised shading as the trees and buildings.
##
## A tile whose sprite is missing on this machine still reads: a silhouette in
## the feature's own colour is painted in its place, so a stripped art folder
## never leaves a bare patch of ground. Rocks and Brush draw one silhouette per
## scattered drawing.

## The sprite art lives here as `<feature>_0/_1/_2/_3.png`; `layout.json` next to
## them records the draw scale and normalized tile-centre anchor per file.
const SPRITE_DIR := "res://assets/sprites/terrain/"
const TERRAIN_SPRITE_OCCLUSION: Shader = preload("res://shaders/terrain_sprite_occlusion.gdshader")

## A JSON sidecar used by the bundled sprites: draw scale per feature and the
## normalized anchor of each drawing. See docs/systems/course-design/terrain-art.md.
const ART_LAYOUT_FILE := "layout.json"
const MIN_ART_SCALE := 0.05
const MAX_ART_SCALE := 4.0

## The four drawings a feature can wear, numbered in the order a course's view
## turns (see TerrainGrid.get_view_orientation()). They are alternative drawings
## of the same feature, not four sides of a turning model, so a tile keeps the
## one its own position picked whichever way the course is viewed.
const FACINGS: Array[String] = ["0", "1", "2", "3"]

## The drawing used when nothing asks for a particular one — the toolbar's
## preview reads it, so a button never turns with the course behind it.
const DEFAULT_FACING := 0

## The tiles this overlay draws, and the art key each one wears. The keys are
## filenames in `SPRITE_DIR` and are fixed for the life of the art: a save
## stores terrain ids, never art names.
const FEATURE_KEYS: Dictionary = {
	TerrainTypes.Type.BRUSH: "brush",
	TerrainTypes.Type.ROCKS: "rocks",
	TerrainTypes.Type.BOULDER: "boulder",
}

## The same set in toolbar order, for tooltips and tests.
const FEATURE_TILES: Array[int] = [
	TerrainTypes.Type.BRUSH, TerrainTypes.Type.ROCKS, TerrainTypes.Type.BOULDER,
]

## A feature stands on its tile: a little lean and size change per tile is what
## keeps a rocky field from reading as a rubber stamp. The jitter stays small
## because these sprites tile shoulder to shoulder, unlike a wood's canopies.
const JITTER_X := 3.0
const JITTER_Y := 1.5
const SCALE_MIN := 0.94
const SCALE_MAX := 1.06

## Only the features near the camera need CanvasItems. A small hidden pool
## avoids reallocating sprites while panning without retaining one node per map
## tile.
const MAX_POOLED_VISUALS := 192

## Rocks and Brush are fields, so one tile wears several of their drawings at
## once. Boulder is a single stone and stays a single drawing.
const MULTI_SPRITE_KEYS: Array[String] = ["rocks", "brush"]

## Where a scattered drawing stands, in screen pixels from the tile centre. The
## slots are the corners of the tile's footprint rather than its middle: two or
## three drawings at 17 px out read as separate stones or bushes, where a
## centre slot and two close neighbours would bunch into one clump.
const STAMP_SLOTS: Array[Vector2] = [
	Vector2(-17.0, 2.0),   # left
	Vector2(17.0, 2.0),    # right
	Vector2(0.0, -10.0),   # back
	Vector2(0.0, 6.0),     # front
]
const MIN_STAMPS := 2
const MAX_STAMPS := 3

## Salt that keeps the scatter RNG out of the base jitter/scale draws shared with
## the occlusion material (`ground_jitter()`, `variation_for_tile()`).
const STAMP_SEED_SALT := 0x51ed270b

var terrain_grid: TerrainGrid
var _visuals: Dictionary = {}  # visible Vector2i -> stamp container Node2D
var _pooled_visuals: Array[Node2D] = []
var _feature_tiles: Dictionary = {}  # Vector2i -> art key drawn on that tile
var _visual_sync_pending := false
var _occlusion_enabled := false
var _last_visible_min := Vector2i(-1, -1)
var _last_visible_max := Vector2i(-1, -1)

static var _texture_cache: Dictionary = {}  # sprite path -> Texture2D (or null)
static var _layout_data: Dictionary = {}
static var _layout_cache: Dictionary = {}  # sprite path -> Dictionary
static var _layout_loaded := false

func initialize(grid: TerrainGrid) -> void:
	terrain_grid = grid
	# Ground detail shares the terrain band and the world Y-sort, so a rocky
	# tile in front covers a scrub tile behind it.
	z_index = 1
	y_sort_enabled = true
	texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_occlusion_enabled = _should_enable_occlusion()
	EventBus.terrain_tile_changed.connect(_on_terrain_tile_changed)
	EventBus.load_completed.connect(_on_load_completed)
	EventBus.view_rotated.connect(_on_view_rotated)
	terrain_grid.vertex_elevation_changed.connect(_on_vertex_elevation_changed)
	PerformanceSettings.profile_changed.connect(_on_performance_profile_changed)
	rescan()

func _exit_tree() -> void:
	if EventBus.terrain_tile_changed.is_connected(_on_terrain_tile_changed):
		EventBus.terrain_tile_changed.disconnect(_on_terrain_tile_changed)
	if EventBus.load_completed.is_connected(_on_load_completed):
		EventBus.load_completed.disconnect(_on_load_completed)
	if EventBus.view_rotated.is_connected(_on_view_rotated):
		EventBus.view_rotated.disconnect(_on_view_rotated)
	if is_instance_valid(terrain_grid) and terrain_grid.vertex_elevation_changed.is_connected(_on_vertex_elevation_changed):
		terrain_grid.vertex_elevation_changed.disconnect(_on_vertex_elevation_changed)
	if PerformanceSettings.profile_changed.is_connected(_on_performance_profile_changed):
		PerformanceSettings.profile_changed.disconnect(_on_performance_profile_changed)

## Rebuild the lightweight tile index after a load, generated course or theme
## change. Sprite CanvasItems are made only for the camera's visible tile range.
func rescan() -> void:
	_refresh_occlusion_mode(true)
	_feature_tiles.clear()
	if terrain_grid:
		for x in range(terrain_grid.grid_width):
			for y in range(terrain_grid.grid_height):
				var pos := Vector2i(x, y)
				var key := feature_key(terrain_grid.get_tile(pos))
				if not key.is_empty():
					_feature_tiles[pos] = key
	_sync_visuals()

# =============================================================================
# ART LOOKUP — the toolbar's feature tiles read their preview from here too
# =============================================================================

## Is this terrain tile drawn with a sprite by this overlay?
static func is_feature_tile(type: int) -> bool:
	return FEATURE_KEYS.has(type)

## The art key a tile wears ("brush", "rocks", "boulder"), or "" for a tile
## this overlay does not draw.
static func feature_key(type: int) -> String:
	return str(FEATURE_KEYS.get(type, ""))

## The file suffix of the drawing `facing` ("0", "1", "2" or "3"). Orientations
## outside 0..3 wrap, as the view itself does.
static func facing_name(facing: int) -> String:
	return FACINGS[wrapi(facing, 0, FACINGS.size())]

## The stable drawing assigned to the tile. `view` remains accepted for callers
## that pass an orientation too, but terrain turns never change the art variant.
static func facing_at(pos: Vector2i, _view: int = DEFAULT_FACING) -> int:
	return facing_offset(pos)

## How many drawings this tile stands apart from the first: 0..3, one per tile,
## the same on every machine and every reload. A mixed hash rather than a cheap
## `x + y` so a rocky field does not sort itself into diagonal stripes of
## identical outcrops.
static func facing_offset(pos: Vector2i) -> int:
	var hash_value := (pos.x * 0x1f1f1f1f + pos.y * 0x27d4eb2d) & 0x7FFFFFFF
	hash_value = ((hash_value ^ (hash_value >> 15)) * 0x85ebca6b) & 0x7FFFFFFF
	hash_value = (hash_value ^ (hash_value >> 13)) * 0xc2b2ae35
	hash_value = (hash_value ^ (hash_value >> 16)) & 0x7FFFFFFF
	return hash_value % FACINGS.size()

## The sprite a feature wears at drawing `facing`, or "" when this machine has
## no art for it and the tile falls back to its silhouette. An unsuffixed
## drawing, then variant 0, fills any variant that has not been supplied.
static func sprite_path(key: String, facing: int = DEFAULT_FACING) -> String:
	if key.is_empty():
		return ""
	var suffixes: Array[String] = ["_" + facing_name(facing), "", "_" + FACINGS[DEFAULT_FACING]]
	for suffix in suffixes:
		var path: String = SPRITE_DIR + key + suffix + ".png"
		if ResourceLoader.exists(path):
			return path
	return ""

## The loaded texture for a feature at one drawing, or null when it has no art.
static func texture_for(key: String, facing: int = DEFAULT_FACING) -> Texture2D:
	return texture_at(sprite_path(key, facing))

## The texture at a path this lookup returned, cached by path. A missing file
## is remembered as null so it is looked up once, not on every tile redraw.
static func texture_at(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if not _texture_cache.has(path):
		var loaded: Texture2D = null
		if ResourceLoader.exists(path):
			loaded = load(path) as Texture2D
		_texture_cache[path] = loaded
	return _texture_cache[path]

## The layout settings for one drawing: the feature's scale under the
## drawing's own normalized tile-centre anchor.
static func _layout_for_path(path: String) -> Dictionary:
	if _layout_cache.has(path):
		return _layout_cache[path]
	if not _layout_loaded:
		_layout_data = _read_layout()
		_layout_loaded = true
	var stem := path.get_file().get_basename()
	var key := stem
	for candidate in FACINGS:
		var suffix := "_" + candidate
		if stem.length() > suffix.length() and stem.ends_with(suffix):
			key = stem.substr(0, stem.length() - suffix.length())
			break
	var result: Dictionary = {}
	var features: Dictionary = _layout_data.get("features", {})
	var feature_values: Variant = features.get(key, {})
	if feature_values is Dictionary:
		result.merge(feature_values, true)
	var sprites: Dictionary = _layout_data.get("sprites", {})
	var sprite_values: Variant = sprites.get(stem, {})
	if sprite_values is Dictionary:
		result.merge(_layout_values(sprite_values), true)
	_layout_cache[path] = result
	return result

## Read the bundled layout once. A malformed file is ignored rather than fatal:
## the art then draws at native size and its own centre.
static func _read_layout() -> Dictionary:
	var path := SPRITE_DIR + ART_LAYOUT_FILE
	if not FileAccess.file_exists(path):
		return {}
	var json := JSON.new()
	if json.parse(FileAccess.get_file_as_string(path)) != OK or not (json.data is Dictionary):
		return {}
	var raw: Dictionary = json.data
	return {
		"features": _layout_entries(raw.get("features", {})),
		"sprites": _layout_entries(raw.get("sprites", {})),
	}

## The usable numeric fields from one layout entry. Scale is clamped so a typo
## cannot make a zero-sized sprite or swallow the whole course; anchors are
## clamped to the canvas.
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
		var value: Variant = raw.get(field, null)
		if value is int or value is float:
			result[field] = clampf(float(value), 0.0, 1.0)
	return result

## The map form of `features` and `sprites`: only entries with a usable field
## survive, so a misspelled key harmlessly falls back to the broader rule.
static func _layout_entries(raw: Variant) -> Dictionary:
	var result: Dictionary = {}
	if not (raw is Dictionary):
		return result
	for key in raw:
		var values := _layout_values(raw[key])
		if not values.is_empty():
			result[str(key)] = values
	return result

## The scale a loaded art file is drawn at.
static func art_scale(path: String) -> float:
	var layout := _layout_for_path(path)
	return clampf(float(layout.get("scale", 1.0)), MIN_ART_SCALE, MAX_ART_SCALE)

static func art_offset_x(path: String) -> float:
	return float(_layout_for_path(path).get("offset_x", 0.0))

static func art_offset_y(path: String) -> float:
	return float(_layout_for_path(path).get("offset_y", 0.0))

## The 2D offset from the image's centre to its terrain anchor (the tile
## centre). Ratios keep the anchor correct when a drawing's canvas differs in
## size, which every variant of an outcrop does.
static func art_anchor_offset(key: String, path: String, source_size: Vector2,
		variation_scale: float = 1.0) -> Vector2:
	if key.is_empty():
		return Vector2.ZERO
	var layout := _layout_for_path(path)
	var scale_value := art_scale(path) * variation_scale
	var anchor_x := 0.0
	if layout.has("ground_x") or layout.has("ground_x_ratio"):
		var ground_x := float(layout.get("ground_x",
				source_size.x * float(layout.get("ground_x_ratio", 0.5))))
		anchor_x = (ground_x - source_size.x * 0.5) * scale_value
	var anchor_y := 0.0
	if layout.has("ground_y") or layout.has("ground_y_ratio"):
		var ground_y := float(layout.get("ground_y",
				source_size.y * float(layout.get("ground_y_ratio", 0.5))))
		anchor_y = (ground_y - source_size.y * 0.5) * scale_value
	return Vector2(anchor_x, anchor_y)

## How far the bottom edge of a drawing's canvas sits below the tile-centre
## anchor it is drawn around. Ground-cover art keeps a painted skirt below that
## anchor, so it is the canvas bottom - not the anchor - that rests on the
## terrain. The occlusion material is pinned there: ground in front of a pixel
## below the anchor would otherwise clip the whole skirt in one flat line.
static func art_bottom_offset(key: String, path: String, scale_v: float) -> float:
	var texture := texture_at(path)
	if texture == null:
		return 0.0
	var source_size := texture.get_size()
	var size := source_size * scale_v * art_scale(path)
	var anchor := art_anchor_offset(key, path, source_size, scale_v)
	return size.y * 0.5 - anchor.y + art_offset_y(path)

## Forget the loaded textures and layout — what the tests use, and what a
## future art pack replacing the folder on disk needs.
static func clear_art_cache() -> void:
	_texture_cache.clear()
	_layout_cache.clear()
	_layout_data.clear()
	_layout_loaded = false

## The one RNG seed per tile. Deliberately salted differently from
## `TreeOverlay.variation_seed()`: a rock and a tree sharing a tile never share
## a lean, and the value is stable on every machine and every reload.
static func variation_seed(pos: Vector2i) -> int:
	return pos.x * 73856093 ^ pos.y * 19349663

## The small screen-space offset also supplied to the occlusion material. Keep
## this sequence identical to the two jitter draws at the start of
## `_on_stamp_draw()`.
static func ground_jitter(pos: Vector2i) -> Vector2:
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed(pos)
	return Vector2(rng.randf_range(-JITTER_X, JITTER_X), rng.randf_range(-JITTER_Y, JITTER_Y))

## Deterministic per-tile jitter and scale matching `_on_stamp_draw()` without
## creating an overlay node.
static func variation_for_tile(pos: Vector2i) -> Dictionary:
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed(pos)
	var jitter := Vector2(rng.randf_range(-JITTER_X, JITTER_X), rng.randf_range(-JITTER_Y, JITTER_Y))
	var scale_v := rng.randf_range(SCALE_MIN, SCALE_MAX)
	return {"jitter": jitter, "scale": scale_v}

## True when one tile wears several drawings of this feature (Rocks, Brush).
static func uses_multiple_sprites(key: String) -> bool:
	return MULTI_SPRITE_KEYS.has(key)

## The drawings one tile wears, in the order they should be painted: a
## Dictionary per drawing with its `variant`, its screen `offset` from the tile
## centre and its `scale`. A single-drawing feature returns one entry at the
## centre. Rocks and Brush return two or three entries, each a different
## variant, spread across the tile, so a tile shows several stones or bushes
## rather than one stamp repeated. Deterministic for a tile and independent of
## the course's view, like `facing_at()`.
static func stamps_for(key: String, pos: Vector2i,
		facing: int = DEFAULT_FACING) -> Array[Dictionary]:
	if not uses_multiple_sprites(key):
		return [{"variant": facing, "offset": Vector2.ZERO, "scale": 1.0}]
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed(pos) ^ STAMP_SEED_SALT
	var count := rng.randi_range(MIN_STAMPS, MAX_STAMPS)
	var slot_start := rng.randi_range(0, STAMP_SLOTS.size() - 1)
	var stamps: Array[Dictionary] = []
	for i in range(count):
		var slot := (slot_start + i) % STAMP_SLOTS.size()
		var offset: Vector2 = STAMP_SLOTS[slot] + Vector2(
				rng.randf_range(-1.5, 1.5), rng.randf_range(-1.5, 1.5))
		stamps.append({
			"variant": wrapi(facing + i, 0, FACINGS.size()),
			"offset": offset,
			"scale": rng.randf_range(0.90, 1.10),
		})
	# Low objects on one ground plane: paint the back-most first so a front
	# stone or bush overlaps its neighbour, exactly as two tiles would.
	stamps.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return a["offset"].y < b["offset"].y)
	return stamps

# =============================================================================
# EVENTS AND VISIBLE-SET SYNC
# =============================================================================

func _on_load_completed(_success: bool) -> void:
	rescan()

func _on_view_rotated(_orientation: int, _isometric: bool) -> void:
	# The visible tile window can remain unchanged while every tile-local scatter
	# and view-facing sprite has moved. Reposition/redraw the active nodes too.
	_sync_visible_features(true)

func _on_performance_profile_changed(_low_detail: bool) -> void:
	var previous_occlusion := _occlusion_enabled
	_refresh_occlusion_mode()
	if previous_occlusion != _occlusion_enabled:
		for container in _visuals.values():
			for stamp in (container as Node2D).get_children():
				(stamp as Node2D).queue_redraw()

func _on_vertex_elevation_changed(vertex: Vector2i, _old: int, _new: int) -> void:
	_refresh_occlusion_mode()
	for pos in terrain_grid.tiles_around_vertex(vertex):
		if not _visuals.has(pos):
			continue
		var container: Node2D = _visuals[pos]
		var new_position := terrain_grid.grid_to_screen_center(pos)
		if container.position != new_position:
			container.position = new_position
		for stamp in container.get_children():
			_update_stamp_anchor(pos, stamp)

## Bulk elevation loads do not emit one vertex signal per point. Refresh only
## the currently visible features after such a load.
func refresh_elevation_visuals() -> void:
	_refresh_occlusion_mode(true)
	for pos in _visuals:
		var container: Node2D = _visuals[pos]
		container.position = terrain_grid.grid_to_screen_center(pos)
		for stamp in container.get_children():
			_update_stamp_anchor(pos, stamp)

func _on_terrain_tile_changed(tile_pos: Vector2i, old_type: int, new_type: int) -> void:
	var new_key := feature_key(new_type)
	var old_key := feature_key(old_type)
	if new_key.is_empty() and old_key.is_empty():
		return # Something else was painted here; the ground cover is unchanged.
	if new_key.is_empty():
		_feature_tiles.erase(tile_pos)
	else:
		_feature_tiles[tile_pos] = new_key
		var container := _visuals.get(tile_pos) as Node2D
		if container:
			# A different feature (or a different outcrop) reuses the tile's
			# CanvasItems, whose cached draw commands still hold the old sprites.
			for stamp in container.get_children():
				(stamp as Node2D).queue_redraw()
	# Tile generation may change thousands of tiles in one frame. Defer the
	# visible-node diff so those edits coalesce into one bounded sync.
	_visual_sync_pending = true
	queue_redraw()

func _draw() -> void:
	if _visual_sync_pending:
		_visual_sync_pending = false
		_sync_visible_features(true)

## Called by TerrainGrid only when the camera's visible range needs refreshing.
func update_visible_features() -> void:
	_sync_visible_features(false)

## Compatibility/test entry point: force the current visible-node set to match
## the full tile index immediately.
func _sync_visuals() -> void:
	_sync_visible_features(true)

## Reproject a feature's authored default-view offset to the same fractional
## point on its tile. TerrainGrid includes the local heightfield so bases follow
## both course rotation and sculpted slopes without rotating the sprite itself.
func _tile_surface_offset(pos: Vector2i, offset: Vector2) -> Vector2:
	if terrain_grid == null:
		return offset
	return terrain_grid.tile_local_screen_offset(pos, offset)

func _sync_visible_features(force_membership: bool) -> void:
	if terrain_grid == null:
		return
	var tile_range := terrain_grid.get_visible_tile_range()
	if tile_range.size() < 2:
		return
	var first: Vector2i = tile_range[0]
	var last: Vector2i = tile_range[1]
	if not force_membership and first == _last_visible_min and last == _last_visible_max:
		return
	_last_visible_min = first
	_last_visible_max = last

	var desired: Dictionary = {}
	if last.x >= first.x and last.y >= first.y:
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				var pos := Vector2i(x, y)
				if _feature_tiles.has(pos):
					desired[pos] = true

	for pos in _visuals.keys():
		if not desired.has(pos):
			_release_visual(pos)

	for pos in desired:
		var key: String = _feature_tiles[pos]
		var stamps := stamps_for(key, pos, facing_at(pos))
		var container: Node2D
		if _visuals.has(pos):
			container = _visuals[pos]
		else:
			container = _obtain_visual()
			container.set_meta("feature_pos", pos)
			container.name = "Feature_%d_%d" % [pos.x, pos.y]
			container.visible = true
			_visuals[pos] = container
		_ensure_stamp_count(container, stamps.size())
		container.position = terrain_grid.grid_to_screen_center(pos)

		var jitter := ground_jitter(pos)
		var tile_scale := float(variation_for_tile(pos)["scale"])
		for i in range(stamps.size()):
			var stamp: Node2D = container.get_child(i)
			var stamp_offset: Vector2 = stamps[i]["offset"]
			var path := sprite_path(key, int(stamps[i]["variant"]))
			var stamp_scale := tile_scale * float(stamps[i]["scale"])
			# Keep the authored scatter coordinate and sample its real terrain
			# height; only the sprite image's own skirt remains a screen offset.
			var tile_offset := jitter + stamp_offset
			var art_ground_offset := Vector2(art_offset_x(path),
					art_offset_y(path) + art_bottom_offset(key, path, stamp_scale))
			stamp.set_meta("feature_pos", pos)
			stamp.set_meta("stamp_index", i)
			stamp.set_meta("tile_offset", tile_offset)
			stamp.set_meta("art_ground_offset", art_ground_offset)
			_update_stamp_anchor(pos, stamp)
			stamp.queue_redraw()

## Replant a stamp on the exact fractional terrain point that its authored
## default-view offset represents. This also refreshes the shader's ground
## anchor, keeping Y-sort and hill occlusion in agreement with the sprite base.
func _update_stamp_anchor(pos: Vector2i, stamp: Node2D) -> void:
	var tile_offset: Vector2 = stamp.get_meta("tile_offset", Vector2.ZERO)
	var ground_grid := terrain_grid.tile_local_grid_point(pos, tile_offset)
	var parent := stamp.get_parent() as Node2D
	if parent != null:
		stamp.position = terrain_grid.grid_point_to_screen(ground_grid) - parent.position
	stamp.set_meta("occlusion_grid", ground_grid)
	_configure_occlusion(stamp, ground_grid,
			stamp.get_meta("art_ground_offset", Vector2.ZERO))

func _obtain_visual() -> Node2D:
	var container: Node2D
	if not _pooled_visuals.is_empty():
		container = _pooled_visuals.pop_back()
	else:
		container = Node2D.new()
		# Each drawing is its own CanvasItem under this container, so the
		# container only Y-sorts them; it draws nothing itself.
		container.y_sort_enabled = true
		add_child(container)
	return container

## Grow or shrink a tile's container to exactly one CanvasItem per drawing.
func _ensure_stamp_count(container: Node2D, count: int) -> void:
	while container.get_child_count() > count:
		var extra := container.get_child(container.get_child_count() - 1)
		container.remove_child(extra)
		extra.queue_free()
	while container.get_child_count() < count:
		var stamp := Node2D.new()
		stamp.name = "Stamp%d" % container.get_child_count()
		stamp.draw.connect(_on_stamp_draw.bind(stamp))
		container.add_child(stamp)

func _release_visual(pos: Vector2i) -> void:
	var container: Node2D = _visuals[pos]
	_visuals.erase(pos)
	container.visible = false
	container.set_meta("feature_pos", Vector2i(-1, -1))
	for stamp in container.get_children():
		stamp.set_meta("feature_pos", Vector2i(-1, -1))
	if _pooled_visuals.size() < MAX_POOLED_VISUALS:
		_pooled_visuals.append(container)
	else:
		container.queue_free()

func _on_stamp_draw(stamp: Node2D) -> void:
	var pos: Vector2i = stamp.get_meta("feature_pos", Vector2i(-1, -1))
	if not _feature_tiles.has(pos):
		return
	var index := int(stamp.get_meta("stamp_index", 0))
	var key: String = _feature_tiles[pos]
	var stamps := stamps_for(key, pos, facing_at(pos))
	if index < 0 or index >= stamps.size():
		return
	var stamp_data: Dictionary = stamps[index]
	var path := sprite_path(key, int(stamp_data["variant"]))
	var texture := texture_at(path)
	var scale_v := float(variation_for_tile(pos)["scale"]) * float(stamp_data["scale"])
	if texture != null:
		_draw_art(stamp, texture, path, key, Vector2.ZERO, scale_v)
	else:
		_draw_silhouette(stamp, Vector2.ZERO, key, scale_v, pos)

func _redraw_active_visuals() -> void:
	for pos in _visuals:
		var container: Node2D = _visuals[pos]
		for stamp in container.get_children():
			_update_stamp_anchor(pos, stamp)
			(stamp as Node2D).queue_redraw()

func _should_enable_occlusion() -> bool:
	return terrain_grid != null and terrain_grid.has_relief() \
		and PerformanceSettings.tree_occlusion_enabled

func _refresh_occlusion_mode(force: bool = false) -> void:
	var should_enable := _should_enable_occlusion()
	if not force and should_enable == _occlusion_enabled:
		return
	_occlusion_enabled = should_enable
	for pos in _visuals:
		var container: Node2D = _visuals[pos]
		for stamp in container.get_children():
			_update_stamp_anchor(pos, stamp)
	for container in _pooled_visuals:
		if not _occlusion_enabled:
			for stamp in container.get_children():
				(stamp as Node2D).material = null

func _configure_occlusion(feature: Node2D, ground_grid: Vector2,
		ground_offset: Vector2) -> void:
	if not _occlusion_enabled or terrain_grid == null or terrain_grid._course_surface == null:
		feature.material = null
		return
	var occlusion_material := feature.material as ShaderMaterial
	if occlusion_material == null or occlusion_material.shader != TERRAIN_SPRITE_OCCLUSION:
		occlusion_material = ShaderMaterial.new()
		occlusion_material.shader = TERRAIN_SPRITE_OCCLUSION
		feature.material = occlusion_material
	terrain_grid._course_surface.configure_sprite_occlusion(
			occlusion_material, ground_grid, ground_offset)

# =============================================================================
# DRAWING
# =============================================================================

## One drawing of a feature: laid so its own anchor (the tile centre it was
## cropped around) falls on `center`.
func _draw_art(canvas: Node2D, texture: Texture2D, path: String, key: String,
		center: Vector2, scale_v: float) -> void:
	var source_size := texture.get_size()
	var size := source_size * scale_v * art_scale(path)
	var anchor := art_anchor_offset(key, path, source_size, scale_v)
	var top_left := center - size * 0.5 - anchor
	top_left += Vector2(art_offset_x(path), art_offset_y(path))
	canvas.draw_texture_rect(texture, Rect2(top_left, size), false)

## Fallback art: the feature's shape in its own colour, so a stripped art
## folder still shows scrub and stone rather than a bare patch of ground.
func _draw_silhouette(canvas: Node2D, center: Vector2, key: String, scale_v: float,
		pos: Vector2i) -> void:
	var tile_type := TerrainTypes.Type.ROCKS
	for candidate in FEATURE_KEYS:
		if FEATURE_KEYS[candidate] == key:
			tile_type = candidate
			break
	var stone := TerrainTypes.get_color(tile_type)
	var rng := RandomNumberGenerator.new()
	rng.seed = variation_seed(pos)
	match key:
		"brush":
			var foliage := Color(0.28, 0.40, 0.17)
			_draw_blob(canvas, center + Vector2(0.0, -10.0 * scale_v),
					13.0 * scale_v, foliage)
			_draw_blob(canvas, center + Vector2(-8.0 * scale_v, -6.0 * scale_v),
					8.0 * scale_v, foliage.lightened(0.08))
			_draw_blob(canvas, center + Vector2(8.0 * scale_v, -7.0 * scale_v),
					7.5 * scale_v, foliage.darkened(0.06))
			canvas.draw_rect(Rect2(center + Vector2(-1.5, -7.0) * scale_v,
					Vector2(3.0, 7.0) * scale_v), Color(0.30, 0.23, 0.14))
		"boulder":
			_draw_blob(canvas, center + Vector2(0.0, -9.0 * scale_v),
					12.0 * scale_v, stone)
			_draw_blob(canvas, center + Vector2(7.0 * scale_v, -4.0 * scale_v),
					6.0 * scale_v, stone.darkened(0.06))
			_draw_blob(canvas, center + Vector2(-2.0 * scale_v, -17.0 * scale_v),
					6.5 * scale_v, stone.lightened(0.12))
		_:
			for i in 4:
				var offset := Vector2(rng.randf_range(-12.0, 12.0),
						rng.randf_range(-7.0, 6.0)) * scale_v
				var radius := rng.randf_range(3.0, 6.0) * scale_v
				_draw_blob(canvas, center + offset + Vector2(0.0, -radius * 0.4),
						radius, stone.lightened(rng.randf_range(-0.05, 0.12)))

## An irregular stone/scrub blob, so a fallback shape is never a drawn circle.
func _draw_blob(canvas: Node2D, center: Vector2, radius: float, color: Color) -> void:
	var points := PackedVector2Array()
	for i in range(8):
		var angle := i * TAU / 8.0
		var r := radius * (0.82 + 0.18 * sin(angle * 3.0))
		points.append(center + Vector2(cos(angle), sin(angle) * 0.82) * r)
	canvas.draw_colored_polygon(points, color)
