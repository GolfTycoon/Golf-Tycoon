extends GameTest
## The mini map: a two-to-one diamond of the course that navigates in every view
## orientation and outlines what the camera sees.

var grid: TerrainGrid
var mini_map: MiniMap

func before_each() -> void:
	super()
	# The responsive HUD adapts to window size; pin a standard desktop window
	# so the standard-size map (MiniMap.MAP_SIZE) applies.
	get_window().size = Vector2i(1600, 1000)
	await process_frames(2)
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	mini_map = MiniMap.new()
	mini_map.setup(grid, null, null)
	add_child_autofree(mini_map)

func test_map_is_a_two_to_one_diamond() -> void:
	var polygon := mini_map._map_polygon()
	assert_eq(polygon[0], Vector2(92, 2))
	assert_eq(polygon[1], Vector2(182, 47))
	assert_eq(polygon[2], Vector2(92, 92))
	assert_eq(polygon[3], Vector2(2, 47))
	assert_true(mini_map._is_within_map(Vector2(92, 47)))
	assert_false(mini_map._is_within_map(Vector2(3, 3)))
	assert_false(mini_map._has_point(Vector2(181, 91)))

func test_navigation_matches_projection_in_every_orientation() -> void:
	for orientation in range(4):
		grid.set_view_orientation(orientation)
		assert_true(grid.is_view_isometric())
		var point := Vector2(3.5, 8.5)
		var map_pos := mini_map._grid_to_map_pos(point)
		assert_true(mini_map._is_within_map(map_pos))
		var world := mini_map._map_to_world_pos(map_pos)
		assert_almost_eq(world.x, grid.projection.project(point).x, 0.001)
		assert_almost_eq(world.y, grid.projection.project(point).y, 0.001)

func test_camera_rect_preserves_actual_viewport() -> void:
	var viewport := Rect2(200, 100, 400, 200)
	mini_map.set_camera_rect(viewport, 16, 16)
	assert_eq(mini_map._camera_rect, viewport)

func test_minimap_follows_enabled_preference_and_hud_visibility() -> void:
	assert_true(mini_map.visible, "Minimap starts visible by default")
	GameManager.set_minimap_enabled(false)
	assert_false(mini_map.visible, "Disabling minimap_enabled hides the minimap")
	GameManager.set_minimap_enabled(true)
	assert_true(mini_map.visible, "Enabling minimap_enabled shows the minimap")

	mini_map.hud_visible = false
	assert_false(mini_map.visible, "Hiding the gameplay HUD hides the minimap")
	GameManager.set_minimap_enabled(false)
	GameManager.set_minimap_enabled(true)
	assert_false(mini_map.visible, "Enabling the setting while the HUD is hidden keeps the minimap hidden")
	mini_map.hud_visible = true
	assert_true(mini_map.visible, "Showing the gameplay HUD reveals the enabled minimap")

func test_display_settings_restore_minimap_preference() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "minimap_enabled", false)
	SaveManager._apply_display_settings(config)
	assert_false(GameManager.minimap_enabled)
	assert_false(mini_map.visible)

	var defaults := ConfigFile.new()
	SaveManager._apply_display_settings(defaults)
	assert_true(GameManager.minimap_enabled)
	assert_true(mini_map.visible)
