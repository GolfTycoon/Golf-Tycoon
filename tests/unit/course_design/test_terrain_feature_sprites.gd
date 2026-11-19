extends GameTest
## The sprite art and drawing of the Brush, Rocks and Boulder terrain tiles.
##
## These three tiles are objects rather than patterns: each is one terrain id
## whose ground the course surface paints and whose sprite
## `TerrainFeatureOverlay` stands on top, the arrangement a woodland tile and
## `TreeOverlay` already share. This file pins the pieces a player sees:
##
## * every feature ships four independently drawn variants, and every one loads;
## * `layout.json` anchors each drawing by its own canvas size, because the
##   variants are cropped to different silhouettes;
## * the toolbar preview reads the first drawing;
## * a painted tile gets one CanvasItem at its own projected centre, in the
##   ground band, below the standing trees;
## * the variant a tile wears is a mixed hash of its position, deterministic and
##   independent of the course's view.
##
## The art itself is baked by `tools/terrain_art/generate.py` (see
## `tools/terrain_art/features.py`); `--check` there fails when the committed
## PNGs no longer match their models.

const LAYOUT_PATH := "res://assets/sprites/terrain/layout.json"

var grid: TerrainGrid


func before_each() -> void:
	super()
	TerrainFeatureOverlay.clear_art_cache()
	grid = make_grid(16, 16)
	fill_grid(grid, TerrainTypes.Type.GRASS)


func _layout() -> Dictionary:
	var json := JSON.new()
	assert_eq(json.parse(FileAccess.get_file_as_string(LAYOUT_PATH)), OK,
			"the sprite layout sidecar parses")
	return json.data


# ---------------------------------------------------------------------------
# The art: four drawings per feature, each anchored by its own canvas
# ---------------------------------------------------------------------------

func test_every_feature_tile_has_a_key_and_four_loadable_drawings() -> void:
	for type in TerrainFeatureOverlay.FEATURE_TILES:
		var key := TerrainFeatureOverlay.feature_key(type)
		assert_false(key.is_empty(), "%d is drawn as a feature sprite" % type)
		assert_true(TerrainFeatureOverlay.is_feature_tile(type))
		var seen: Dictionary = {}
		for facing in range(TerrainFeatureOverlay.FACINGS.size()):
			var suffix := TerrainFeatureOverlay.facing_name(facing)
			var path := TerrainFeatureOverlay.sprite_path(key, facing)
			assert_eq(path, TerrainFeatureOverlay.SPRITE_DIR + "%s_%s.png" % [key, suffix],
					"%s wears its %s drawing" % [key, suffix])
			assert_false(seen.has(path), "and it is its own file, not a repeat")
			assert_not_null(TerrainFeatureOverlay.texture_at(path),
					"%s loads" % path)
			seen[path] = true
		assert_eq(seen.size(), TerrainFeatureOverlay.FACINGS.size(),
				"%s ships one file per drawing" % key)
		assert_false(TerrainFeatureOverlay.sprite_path("").length() > 0,
				"no key means no sprite")


func test_layout_anchors_every_drawing_on_its_own_canvas() -> void:
	var layout := _layout()
	var sprites: Dictionary = layout.get("sprites", {})
	var differing_canvases := false
	for type in TerrainFeatureOverlay.FEATURE_TILES:
		var key := TerrainFeatureOverlay.feature_key(type)
		var first_size := Vector2.ZERO
		for facing in range(TerrainFeatureOverlay.FACINGS.size()):
			var suffix := TerrainFeatureOverlay.facing_name(facing)
			var path := TerrainFeatureOverlay.sprite_path(key, facing)
			var texture := TerrainFeatureOverlay.texture_at(path)
			var source_size := texture.get_size()
			if facing == 0:
				first_size = source_size
			elif source_size != first_size:
				differing_canvases = true
			assert_true(sprites.has("%s_%s" % [key, suffix]),
					"layout records the anchor of %s_%s" % [key, suffix])
			var values: Dictionary = sprites["%s_%s" % [key, suffix]]
			var ratio_x := float(values.get("ground_x_ratio", -1.0))
			var ratio_y := float(values.get("ground_y_ratio", -1.0))
			assert_between(ratio_x, 0.02, 0.98,
					"the tile centre is horizontally inside %s_%s" % [key, suffix])
			assert_between(ratio_y, 0.02, 0.98,
					"the tile centre is vertically inside %s_%s" % [key, suffix])
			var scale_value := TerrainFeatureOverlay.art_scale(path)
			var anchor := TerrainFeatureOverlay.art_anchor_offset(key, path, source_size)
			assert_almost_eq(anchor.x,
					(ratio_x - 0.5) * source_size.x * scale_value, 0.001,
					"%s_%s is anchored by its own width" % [key, suffix])
			assert_almost_eq(anchor.y,
					(ratio_y - 0.5) * source_size.y * scale_value, 0.001,
					"%s_%s is anchored by its own height" % [key, suffix])
	assert_true(differing_canvases,
			"the drawings have different canvases, so the ratios do real work")


func test_the_default_drawing_is_the_authored_first_file() -> void:
	for key in ["brush", "rocks", "boulder"]:
		assert_eq(TerrainFeatureOverlay.sprite_path(key),
				TerrainFeatureOverlay.SPRITE_DIR + key + "_0.png",
				"%s's preview reads the authored first drawing" % key)
		assert_same(TerrainFeatureOverlay.texture_for(key),
				TerrainFeatureOverlay.texture_for(key, 0))


func test_every_feature_has_a_scale_in_the_layout() -> void:
	var features: Dictionary = _layout().get("features", {})
	for type in TerrainFeatureOverlay.FEATURE_TILES:
		var key := TerrainFeatureOverlay.feature_key(type)
		assert_true(features.has(key), "layout scales %s" % key)
		var path := TerrainFeatureOverlay.sprite_path(key)
		assert_almost_eq(TerrainFeatureOverlay.art_scale(path),
				float(features[key].get("scale", 0.0)), 0.0001,
				"%s is drawn at the layout's scale" % key)


# ---------------------------------------------------------------------------
# The tile index and the drawing itself
# ---------------------------------------------------------------------------

func test_every_painted_feature_tile_gets_a_sprite_at_its_centre() -> void:
	var expected := {
		Vector2i(3, 4): TerrainTypes.Type.BRUSH,
		Vector2i(6, 7): TerrainTypes.Type.ROCKS,
		Vector2i(9, 5): TerrainTypes.Type.BOULDER,
	}
	for pos in expected:
		grid.set_tile(pos, expected[pos])
	grid._feature_overlay._sync_visuals()

	assert_eq(grid._feature_overlay._visuals.size(), expected.size(),
			"one CanvasItem per painted feature tile")
	for pos in expected:
		assert_true(grid._feature_overlay._visuals.has(pos),
				"a %s tile has a sprite" % TerrainFeatureOverlay.feature_key(expected[pos]))
		var visual := grid._feature_overlay._visuals[pos] as Node2D
		assert_eq(visual.position, grid.grid_to_screen_center(pos),
				"the sprite is anchored to the tile's projected centre")
		assert_almost_eq(TerrainFeatureOverlay.ground_jitter(pos).y,
				TerrainFeatureOverlay.variation_for_tile(pos)["jitter"].y, 0.001,
				"the draw and the occlusion shader agree on the jitter")


func test_replacing_a_feature_tile_releases_its_sprite() -> void:
	var pos := Vector2i(5, 5)
	grid.set_tile(pos, TerrainTypes.Type.BOULDER)
	grid._feature_overlay._sync_visuals()
	assert_true(grid._feature_overlay._visuals.has(pos))

	grid.set_tile(pos, TerrainTypes.Type.FAIRWAY)
	grid._feature_overlay._sync_visuals()
	assert_false(grid._feature_overlay._visuals.has(pos),
			"painting fairway over a boulder takes its sprite with it")


func test_a_feature_sprite_reuses_its_tile_when_the_feature_changes() -> void:
	var pos := Vector2i(7, 8)
	grid.set_tile(pos, TerrainTypes.Type.ROCKS)
	grid._feature_overlay._sync_visuals()
	var before := grid._feature_overlay._visuals[pos] as Node2D
	grid.set_tile(pos, TerrainTypes.Type.BRUSH)
	grid._feature_overlay._sync_visuals()
	assert_same(grid._feature_overlay._visuals[pos], before,
			"the tile keeps its CanvasItem and only redraws the new sprite")


func test_a_plain_tile_has_no_feature_sprite() -> void:
	for type in [TerrainTypes.Type.GRASS, TerrainTypes.Type.FAIRWAY,
			TerrainTypes.Type.OAK, TerrainTypes.Type.FLOWER_BED]:
		assert_false(TerrainFeatureOverlay.is_feature_tile(type),
				"%d is not a feature tile" % type)
		assert_eq(TerrainFeatureOverlay.feature_key(type), "")


# ---------------------------------------------------------------------------
# Draw order: ground detail, below the trees and the standing sprites
# ---------------------------------------------------------------------------

func test_feature_sprites_paint_in_the_ground_band_under_the_trees() -> void:
	var overlay := grid.get_node("TerrainFeatureOverlay") as CanvasItem
	assert_eq(overlay.z_index, 1, "features are ground detail, in band 1")
	assert_true(overlay.y_sort_enabled,
			"a front feature tile covers the one behind it")

	var order := TerrainGrid.GROUND_DETAIL_ORDER
	var feature_slot := order.find("TerrainFeatureOverlay")
	assert_gt(feature_slot, order.find("WalkingPathOverlay"),
			"a boulder covers the trail laid under it")
	assert_lt(feature_slot, order.find("TreeOverlay"),
			"a canopy covers the rock beneath it")
	assert_lt(grid.get_node("TerrainFeatureOverlay").get_index(),
			grid.get_node("TreeOverlay").get_index(),
			"and the tree order in the tree matches the ranking")


# ---------------------------------------------------------------------------
# Variants: mixed across the map, fixed per tile, free of the view
# ---------------------------------------------------------------------------

func test_tile_variants_are_mixed_and_deterministic() -> void:
	var seen: Dictionary = {}
	for x in range(8):
		for y in range(8):
			var pos := Vector2i(x, y)
			var variant := TerrainFeatureOverlay.facing_at(pos)
			assert_eq(variant, TerrainFeatureOverlay.facing_offset(pos),
					"the drawing is the tile's own")
			assert_eq(variant, TerrainFeatureOverlay.facing_at(pos),
					"and it never changes from call to call")
			assert_between(variant, 0, TerrainFeatureOverlay.FACINGS.size() - 1)
			seen[variant] = true
	assert_eq(seen.size(), TerrainFeatureOverlay.FACINGS.size(),
			"a stretch of terrain shows every drawing, not one stamp")


func test_per_tile_variation_is_small_and_stable() -> void:
	for pos in [Vector2i(0, 0), Vector2i(5, 9), Vector2i(-3, 12)]:
		var first := TerrainFeatureOverlay.variation_for_tile(pos)
		var second := TerrainFeatureOverlay.variation_for_tile(pos)
		assert_eq(first["jitter"], second["jitter"], "the lean is deterministic")
		assert_eq(first["scale"], second["scale"], "the size is deterministic")
		var jitter: Vector2 = first["jitter"]
		assert_lt(absf(jitter.x), TerrainFeatureOverlay.JITTER_X + 0.001)
		assert_lt(absf(jitter.y), TerrainFeatureOverlay.JITTER_Y + 0.001)
		assert_between(first["scale"], TerrainFeatureOverlay.SCALE_MIN,
				TerrainFeatureOverlay.SCALE_MAX)
		assert_eq(TerrainFeatureOverlay.ground_jitter(pos), jitter,
				"the occlusion shader is given the same offset the sprite is drawn at")
