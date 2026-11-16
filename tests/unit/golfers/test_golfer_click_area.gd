extends GameTest
## The golfer's clickable area (CollisionShape2D) lines up with what the
## player sees on screen: the skin sprite's opaque body from shoes to cap,
## shifted with any `visual_offset`, rather than a small circle stuck around
## the ground under their feet.

const GOLFER_SCENE := preload("res://scenes/entities/golfer.tscn")

func _spawn_golfer(pos: Vector2 = Vector2(120, 120), tier: int = GolferTier.Tier.CASUAL) -> Golfer:
	var golfer := GOLFER_SCENE.instantiate() as Golfer
	golfer.golfer_tier = tier
	golfer.golfer_name = "Tester"
	golfer.position = pos
	add_child_autofree(golfer)
	golfer.set_process(false)
	golfer.set_physics_process(false)
	return golfer

func _click_world(viewport: Viewport, world_pos: Vector2) -> void:
	var motion := InputEventMouseMotion.new()
	motion.position = world_pos
	viewport.push_input(motion, true)

	var down := InputEventMouseButton.new()
	down.button_index = MOUSE_BUTTON_LEFT
	down.pressed = true
	down.position = world_pos
	viewport.push_input(down, true)

	var up := InputEventMouseButton.new()
	up.button_index = MOUSE_BUTTON_LEFT
	up.pressed = false
	up.position = world_pos
	viewport.push_input(up, true)

func _shape_rect(golfer: Golfer) -> Rect2:
	var cs := golfer.get_node("CollisionShape2D") as CollisionShape2D
	var rect_shape := cs.shape as RectangleShape2D
	return Rect2(cs.position - rect_shape.size * 0.5, rect_shape.size)

func test_click_shape_covers_the_skin_sprite_from_feet_to_head() -> void:
	var golfer := _spawn_golfer()
	await process_frames(1)

	assert_true(golfer._use_sprites, "Casual golfer renders with skin sprites")
	var sprite := golfer.sprite_node()
	var tex := sprite.sprite_frames.get_frame_texture(sprite.animation, sprite.frame)
	var metrics := Golfer._sprite_metrics_for(tex)
	var sprite_bounds: Rect2 = metrics["bounds"]
	var expected_rect := Rect2(
		Vector2(0.0, float(metrics["feet_y"])) + sprite_bounds.position,
		sprite_bounds.size
	)

	var click_rect := _shape_rect(golfer)
	assert_almost_eq(click_rect.position.x, expected_rect.position.x, 0.5)
	assert_almost_eq(click_rect.position.y, expected_rect.position.y, 0.5)
	assert_almost_eq(click_rect.size.x, expected_rect.size.x, 0.5)
	assert_almost_eq(click_rect.size.y, expected_rect.size.y, 0.5)

	# Head, torso and shoes all lie inside the click area; ground below feet does not.
	assert_true(click_rect.has_point(Vector2(0.0, -28.0)), "Head is clickable")
	assert_true(click_rect.has_point(Vector2(0.0, -16.0)), "Torso is clickable")
	assert_true(click_rect.has_point(Vector2(0.0, -1.0)), "Shoes are clickable")
	assert_false(click_rect.has_point(Vector2(0.0, 6.0)), "Empty grass below the feet is not")
	assert_false(click_rect.has_point(Vector2(0.0, -38.0)), "Air above the hat is not")

func test_click_shape_tracks_skin_and_facing_direction_pixels() -> void:
	var golfer := _spawn_golfer(Vector2(120, 120), GolferTier.Tier.BEGINNER)
	await process_frames(1)

	var sprite := golfer.sprite_node()
	sprite.play("idle_south-east")
	await process_frames(1)
	var se_rect := _shape_rect(golfer)

	sprite.play("idle_south-west")
	await process_frames(1)
	var sw_rect := _shape_rect(golfer)

	# Beginner carries a golf bag on one side, so facing SE vs SW shifts the sprite horizontally.
	assert_gt(se_rect.get_center().x, 0.0, "South-east sprite shifts right of centre")
	assert_lt(sw_rect.get_center().x, 0.0, "South-west sprite shifts left of centre")
	assert_true(se_rect.has_point(Vector2(10.0, -16.0)), "Bag side is clickable facing south-east")
	assert_false(sw_rect.has_point(Vector2(10.0, -16.0)), "Empty side is not clickable facing south-west")

func test_click_shape_moves_with_visual_offset() -> void:
	var golfer := _spawn_golfer()
	await process_frames(1)
	var base_rect := _shape_rect(golfer)

	golfer.visual_offset = Vector2(18.0, 6.0)
	var shifted_rect := _shape_rect(golfer)

	assert_almost_eq(shifted_rect.position.x, base_rect.position.x + 18.0, 0.5)
	assert_almost_eq(shifted_rect.position.y, base_rect.position.y + 6.0, 0.5)
	assert_true(shifted_rect.has_point(Vector2(18.0, -10.0)),
		"Clicking the shifted torso hits")
	assert_false(shifted_rect.has_point(Vector2(0.0, -16.0)),
		"Clicking the unshifted origin misses once fanned out")

func test_clicking_head_torso_and_feet_in_viewport_selects_golfer() -> void:
	await resize_window(Vector2i(400, 300))
	var vp := get_viewport()
	var prev_picking := vp.physics_object_picking
	vp.physics_object_picking = true

	var golfer := _spawn_golfer(Vector2(160, 140), GolferTier.Tier.CASUAL)
	var clicks := []
	golfer.golfer_selected.connect(func(g: Golfer) -> void: clicks.append(g))
	await wait_frames(2)
	await process_frames(2)

	# Clicking on the sprite's head (even under InfoContainer), torso, and feet all select the golfer.
	_click_world(vp, golfer.position + Vector2(0, -28))
	await wait_frames(2)
	await process_frames(2)
	assert_eq(clicks.size(), 1, "Clicking the head selects the golfer")

	_click_world(vp, golfer.position + Vector2(0, -16))
	await wait_frames(2)
	await process_frames(2)
	assert_eq(clicks.size(), 2, "Clicking the torso selects the golfer")

	_click_world(vp, golfer.position + Vector2(0, -1))
	await wait_frames(2)
	await process_frames(2)
	assert_eq(clicks.size(), 3, "Clicking the shoes selects the golfer")

	# Clicking empty space below the feet, above the head, or beside the sprite does not.
	_click_world(vp, golfer.position + Vector2(0, 6))
	await wait_frames(2)
	await process_frames(2)
	assert_eq(clicks.size(), 3, "Clicking below the feet does not select the golfer")

	_click_world(vp, golfer.position + Vector2(0, -38))
	await wait_frames(2)
	await process_frames(2)
	assert_eq(clicks.size(), 3, "Clicking above the head does not select the golfer")

	_click_world(vp, golfer.position + Vector2(20, -16))
	await wait_frames(2)
	await process_frames(2)
	assert_eq(clicks.size(), 3, "Clicking empty air beside the golfer does not select them")

	# Shifted visual_offset moves the clickable hitbox to match the sprite.
	golfer.visual_offset = Vector2(16, 4)
	await wait_frames(2)
	await process_frames(2)
	_click_world(vp, golfer.position + Vector2(16, -14))
	await wait_frames(2)
	await process_frames(2)
	assert_eq(clicks.size(), 4, "Clicking the fanned-out sprite selects the golfer")
	vp.physics_object_picking = prev_picking

func test_polygon_fallback_click_shape_aligns_with_lifted_body() -> void:
	var golfer := GOLFER_SCENE.instantiate() as Golfer
	golfer.defer_skin_setup = true
	golfer.position = Vector2(100, 100)
	add_child_autofree(golfer)
	golfer.set_process(false)
	golfer.set_physics_process(false)
	await process_frames(1)

	assert_false(golfer._use_sprites, "Deferred golfer without skin setup uses polygon body")
	var click_rect := _shape_rect(golfer)
	assert_true(click_rect.has_point(Vector2(0.0, -24.0)), "Polygon head is clickable")
	assert_true(click_rect.has_point(Vector2(0.0, -14.0)), "Polygon body is clickable")
	assert_true(click_rect.has_point(Vector2(0.0, -1.0)), "Polygon shoes are clickable")
	assert_false(click_rect.has_point(Vector2(0.0, 5.0)), "Below polygon shoes is not clickable")
