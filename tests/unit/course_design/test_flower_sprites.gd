extends GameTest
## Wild Flowers are authored pixel sprites, drawn with nearest-neighbour
## filtering like the woodland sprite art rather than procedural circles.


func test_every_flower_variant_and_ground_cover_sprite_loads() -> void:
	assert_eq(FlowerOverlay.FLOWER_SPRITES.size(), 4,
			"the beds have a small varied sprite palette")
	for i in range(FlowerOverlay.FLOWER_SPRITES.size()):
		var texture := FlowerOverlay.flower_texture(i)
		assert_not_null(texture, "flower variant %d loads" % i)
		assert_eq(texture.get_size(), FlowerOverlay.FLOWER_SIZE,
				"every bloom uses the same crisp pixel canvas")
	assert_not_null(FlowerOverlay.foliage_texture(), "pixel foliage loads too")


func test_the_overlay_uses_nearest_filtering_for_pixel_art() -> void:
	var grid := make_grid(8, 8)
	var flowers := grid.get_node("FlowerOverlay") as FlowerOverlay
	assert_eq(flowers.texture_filter, CanvasItem.TEXTURE_FILTER_NEAREST,
			"scaled flowers stay sharp rather than being blurred")


func test_flower_bed_uses_reproducible_pixel_sprite_choices() -> void:
	var grid := make_grid(8, 8)
	var pos := Vector2i(3, 3)
	grid.set_tile(pos, TerrainTypes.Type.FLOWER_BED)
	var flowers := grid.get_node("FlowerOverlay") as FlowerOverlay
	var first: Dictionary = flowers._flower_positions[pos]
	var first_sprites: Array = []
	for flower in first.flowers:
		first_sprites.append(flower.sprite)
		assert_true(flower.sprite >= 0 and flower.sprite < FlowerOverlay.FLOWER_SPRITES.size(),
				"every bloom references an authored pixel sprite")
	flowers._generate_flowers_for_tile(pos)
	var again: Dictionary = flowers._flower_positions[pos]
	var again_sprites: Array = []
	for flower in again.flowers:
		again_sprites.append(flower.sprite)
	assert_eq(again_sprites, first_sprites,
			"the bed's pixel art stays fixed across redraws and rescans")
