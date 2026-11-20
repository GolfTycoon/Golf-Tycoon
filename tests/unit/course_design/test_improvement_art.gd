extends GameTest
## The baked improvement sprites and their sidecar: every drawing exists, the
## tile-centre foot lies inside its own canvas, the four fronts are distinct,
## and both Path grain maps are present.

func test_every_improvement_has_its_baked_drawings() -> void:
	for key in ImprovementArt.KEYS:
		var drawings := 4 if key in ImprovementArt.DIRECTIONAL else 1
		for i in range(drawings):
			var suffix := str(i)
			var texture := ImprovementArt.texture(key, suffix)
			assert_not_null(texture, "%s_%s.png is baked" % [key, suffix])
			if texture == null:
				continue
			var foot := ImprovementArt.foot_offset(key, suffix)
			assert_between(foot.x, 0.0, float(texture.get_width()),
				"%s_%s foot x lies inside its canvas" % [key, suffix])
			assert_between(foot.y, 0.0, float(texture.get_height()),
				"%s_%s foot y lies inside its canvas" % [key, suffix])
			assert_true(ImprovementArt.below_foot(key, suffix) >= 0.0,
				"%s_%s has a sane ground reach" % [key, suffix])

func test_the_fronts_of_a_directional_prop_are_four_different_drawings() -> void:
	for key in ImprovementArt.DIRECTIONAL:
		var seen := {}
		for i in range(4):
			var texture := ImprovementArt.texture(key, str(i))
			assert_not_null(texture)
			if texture != null:
				seen[texture.get_rid()] = true
		assert_eq(seen.size(), 4, "%s ships four distinct fronts" % key)


func test_the_ball_washer_ships_one_drawing() -> void:
	assert_not_null(ImprovementArt.texture("ball_washer", "0"),
		"the washer has its one drawing")
	assert_null(ImprovementArt.texture("ball_washer", "1"),
		"the washer does not ship a second front")

func test_the_path_has_both_grain_maps() -> void:
	for grain in ["dirt", "paved"]:
		var path := "res://assets/sprites/paths/%s.png" % grain
		assert_true(ResourceLoader.exists(path), "%s grain is baked" % grain)
		var texture: Texture2D = load(path)
		assert_not_null(texture)
		if texture != null:
			assert_eq(texture.get_size(), Vector2(64, 64),
				"%s grain is one seamless tile" % grain)
