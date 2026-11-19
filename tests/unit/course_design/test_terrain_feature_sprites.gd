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
## * a painted tile gets one container at its own projected centre, in the
##   ground band, below the standing trees, and every drawing inside it is its
##   own CanvasItem;
## * Rocks and Brush scatter two or three different variant drawings across that
##   container, while Boulder stands a single drawing;
## * each tile has a deterministic mixed-hash variant that stays fixed as the
##   map turns, while its scatter positions stay aligned with the terrain.
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
			"one stamp container per painted feature tile")
	for pos in expected:
		assert_true(grid._feature_overlay._visuals.has(pos),
				"a %s tile has a sprite" % TerrainFeatureOverlay.feature_key(expected[pos]))
		var visual := grid._feature_overlay._visuals[pos] as Node2D
		assert_eq(visual.position, grid.grid_to_screen_center(pos),
				"the tile's container is anchored to its projected centre")
		var key := TerrainFeatureOverlay.feature_key(expected[pos])
		var stamps := TerrainFeatureOverlay.stamps_for(key, pos, TerrainFeatureOverlay.DEFAULT_FACING)
		assert_eq(visual.get_child_count(), stamps.size(),
				"every drawing of the tile is its own CanvasItem")
		var jitter := TerrainFeatureOverlay.ground_jitter(pos)
		for i in range(stamps.size()):
			var stamp := visual.get_child(i) as Node2D
			var expected_offset: Vector2 = jitter + Vector2(stamps[i]["offset"])
			assert_almost_eq(stamp.position.x, expected_offset.x, 0.001,
					"drawing %d stays at its tile-local x position" % i)
			assert_almost_eq(stamp.position.y, expected_offset.y, 0.001,
					"drawing %d stays at its tile-local y position" % i)
			assert_eq(stamp.get_meta("stamp_index"), i,
					"drawing %d knows which stamp it is" % i)
		assert_almost_eq(jitter.y,
				TerrainFeatureOverlay.variation_for_tile(pos)["jitter"].y, 0.001,
				"the draw and the occlusion shader agree on the jitter")


func test_every_drawing_clips_against_its_own_painted_base() -> void:
	var pos := Vector2i(4, 2)
	grid.set_tile(pos, TerrainTypes.Type.ROCKS)
	grid._feature_overlay._occlusion_enabled = true
	grid._feature_overlay._sync_visuals()

	var container := grid._feature_overlay._visuals[pos] as Node2D
	assert_gte(container.get_child_count(), 2, "Rocks wears several drawings")
	var materials: Dictionary = {}
	for i in range(container.get_child_count()):
		var stamp := container.get_child(i) as Node2D
		var mat := stamp.material as ShaderMaterial
		assert_not_null(mat, "drawing %d has its own occlusion material" % i)
		materials[mat] = true
		var ground_grid: Vector2 = stamp.get_meta("occlusion_grid")
		assert_eq(mat.get_shader_parameter("ground_grid"), ground_grid,
				"the material clips against drawing %d's terrain point" % i)
		var art_ground_offset: Vector2 = stamp.get_meta("art_ground_offset")
		assert_eq(mat.get_shader_parameter("ground_offset"), art_ground_offset,
				"the material includes only the sprite's authored skirt offset")
		var expected_position := grid.grid_point_to_screen(ground_grid) - container.position
		assert_almost_eq(stamp.position.x, expected_position.x, 0.001,
				"its base stays attached to the projected terrain point")
		assert_almost_eq(stamp.position.y, expected_position.y, 0.001,
				"its base follows the local terrain height")
		var key := TerrainFeatureOverlay.feature_key(TerrainTypes.Type.ROCKS)
		var stamps := TerrainFeatureOverlay.stamps_for(key, pos,
				TerrainFeatureOverlay.facing_at(pos))
		var path := TerrainFeatureOverlay.sprite_path(key, int(stamps[i]["variant"]))
		var scale_v := float(TerrainFeatureOverlay.variation_for_tile(pos)["scale"]) \
				* float(stamps[i]["scale"])
		assert_almost_eq(art_ground_offset.y,
				TerrainFeatureOverlay.art_bottom_offset(key, path, scale_v)
				+ TerrainFeatureOverlay.art_offset_y(path), 0.001,
				"drawing %d clips at the bottom row of its own canvas" % i)
	assert_eq(materials.size(), container.get_child_count(),
			"no two drawings share one silhouette or one clip")

	assert_gt(TerrainFeatureOverlay.art_bottom_offset("boulder",
			TerrainFeatureOverlay.sprite_path("boulder", 0), 1.0), 4.0,
			"a boulder's painted skirt reaches well below its anchor")


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
			"the tile keeps its container and only redraws the new sprite")
	var stamps := TerrainFeatureOverlay.stamps_for("brush", pos, TerrainFeatureOverlay.DEFAULT_FACING)
	assert_eq(before.get_child_count(), stamps.size(),
			"the container grows or shrinks to the new feature's drawings")


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


func test_feature_sprite_variant_stays_fixed_across_course_turns() -> void:
	var tile := Vector2i(4, 7)
	var assigned := TerrainFeatureOverlay.facing_offset(tile)
	for view in range(TerrainFeatureOverlay.FACINGS.size()):
		assert_eq(TerrainFeatureOverlay.facing_at(tile, view), assigned,
				"the feature keeps its sprite variant at view %d" % view)

	var feature_grid := make_grid(16, 16)
	var features := feature_grid.get_node("TerrainFeatureOverlay") as TerrainFeatureOverlay
	var offset := Vector2(17.0, -10.0)
	assert_eq(features._tile_surface_offset(tile, offset), offset,
			"the default view preserves the authored tile point")
	feature_grid.set_view_orientation(2)
	assert_eq(features._tile_surface_offset(tile, offset), -offset,
			"scatter offsets move to the opposite tile point after a half turn")
	feature_grid.set_view_orientation(1)
	var fractional_point := feature_grid.tile_local_grid_point(tile, offset)
	var projected_offset := feature_grid.grid_point_to_screen(fractional_point) \
			- feature_grid.grid_to_screen_center(tile)
	assert_eq(features._tile_surface_offset(tile, offset), projected_offset,
			"the offset follows the isometric basis, not a flat screen rotation")

	feature_grid.set_view_orientation(0)
	var slope_probe := Vector2(1.0, 1.0)
	var flat_anchor := features._tile_surface_offset(tile, slope_probe)
	feature_grid.set_vertex_elevation(tile, TerrainGrid.MAX_ELEVATION)
	var sloped_anchor := features._tile_surface_offset(tile, slope_probe)
	assert_ne(sloped_anchor, flat_anchor,
			"the sprite anchor samples the local terrain height, not just the tile centre")


func test_rocks_and_brush_scatter_several_variant_drawings_on_one_tile() -> void:
	for key in ["rocks", "brush"]:
		var pos := Vector2i(4, 7)
		var stamps := TerrainFeatureOverlay.stamps_for(key, pos, 1)
		assert_true(TerrainFeatureOverlay.uses_multiple_sprites(key),
				"%s scatters several drawings" % key)
		assert_between(stamps.size(), TerrainFeatureOverlay.MIN_STAMPS,
				TerrainFeatureOverlay.MAX_STAMPS)
		var variants: Dictionary = {}
		var offsets: Dictionary = {}
		for stamp in stamps:
			var variant := int(stamp["variant"])
			variants[variant] = true
			offsets[stamp["offset"]] = true
			assert_between(variant, 0, TerrainFeatureOverlay.FACINGS.size() - 1)
			assert_between(float(stamp["scale"]), 0.90, 1.10,
					"each drawing is placed at its own small size")
		assert_eq(variants.size(), stamps.size(),
				"no variation drawing is repeated on one tile")
		assert_eq(offsets.size(), stamps.size(),
				"each drawing stands in its own spot")
		var spots: Array[Vector2] = []
		for stamp in stamps:
			spots.append(stamp["offset"])
		for i in range(spots.size()):
			for j in range(i + 1, spots.size()):
				assert_true((spots[i] - spots[j]).length() >= 12.0,
						"%s drawings are spread apart, not bunched" % key)
		assert_eq(TerrainFeatureOverlay.stamps_for(key, pos, 1), stamps,
				"the scatter is deterministic")
		for i in range(1, stamps.size()):
			var previous: Vector2 = stamps[i - 1]["offset"]
			var current: Vector2 = stamps[i]["offset"]
			assert_true(previous.y <= current.y,
					"the drawings are painted back to front")
		assert_false(TerrainFeatureOverlay.stamps_for(key, Vector2i(4, 8), 1) == stamps,
				"the next tile scatters them differently")


func test_a_boulder_keeps_to_one_drawing() -> void:
	assert_false(TerrainFeatureOverlay.uses_multiple_sprites("boulder"),
			"Boulder is one mass, not a field")
	var stamps := TerrainFeatureOverlay.stamps_for("boulder", Vector2i(2, 3), 2)
	assert_eq(stamps.size(), 1, "one drawing per Boulder tile")
	assert_eq(int(stamps[0]["variant"]), 2, "the tile's own variation")
	assert_eq(stamps[0]["offset"], Vector2.ZERO, "standing on the tile centre")
	assert_eq(float(stamps[0]["scale"]), 1.0)


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
