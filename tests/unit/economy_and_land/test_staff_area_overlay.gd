extends GameTest
## The designated-area overlay projects each staff member's grid-space circle
## into world space so rings render correctly in both course views.

var grid: TerrainGrid
var overlay: StaffAreaOverlay

func before_each() -> void:
	super()
	grid = TerrainGrid.new()
	grid.grid_width = 32
	grid.grid_height = 32
	add_child_autofree(grid)
	overlay = StaffAreaOverlay.new()
	overlay.name = "StaffAreaOverlay"
	overlay.set_terrain_grid(grid)
	add_child_autofree(overlay)

func test_projected_circle_is_a_closed_ring() -> void:
	var points: PackedVector2Array = overlay._projected_circle(Vector2(10, 10), 4.0)
	assert_eq(points.size(), 32)
	# Every sampled point should be a finite world position.
	for point in points:
		assert_true(is_finite(point.x) and is_finite(point.y))
	# A grid-space circle is not degenerate when projected.
	assert_gt(points[0].distance_to(points[16]), 1.0)

func test_highlight_index_defaults_to_none() -> void:
	assert_eq(overlay.highlight_index, -1)

func test_overlay_survives_a_staff_change_with_no_manager() -> void:
	GameManager.staff_manager = null
	overlay.refresh()
	# No crash and no drawn geometry required: the guard returns early.
	assert_eq(overlay.highlight_index, -1)

func test_the_owners_ground_is_drawn_as_its_own_ring() -> void:
	# The owner's own golfer works a ground of their own. It is drawn here
	# too, so the player can see where their golfer is working.
	GameManager.terrain_grid = grid
	var owner_manager := PlayerGolferManager.new()
	add_child_autofree(owner_manager)
	GameManager.player_golfer_manager = owner_manager
	assert_eq(overlay.owner_area_polygon().size(), 0, "With no ground chosen there is no ring to draw")
	assert_true(owner_manager.set_area_center(Vector2i(10, 10)))
	var ring := overlay.owner_area_polygon()
	assert_eq(ring.size(), 32, "The owner's ground is a ring like a staff member's")
	assert_gt(ring[0].distance_to(ring[16]), 1.0, "The ring is drawn around the ground they work")
	# Moving the ground moves the ring with it.
	owner_manager.set_area_center(Vector2i(20, 20))
	assert_ne(overlay.owner_area_polygon()[0], ring[0], "The ring follows the ground they work")
