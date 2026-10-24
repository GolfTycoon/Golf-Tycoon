extends GameTest
## Where the ground art paints, so a wood and a walk can share a tile.
##
## The walking trail and the standing trees are both ground detail: the grid
## paints them in the same band, `z_index` 1, because the entity band opens at 2
## and no whole number is left in between. Items sharing a band are drawn in tree
## order, so whoever was added last covers the rest — which is how a trail came to
## be painted straight through a tree's trunk and crown, the walk cutting the
## sprite in half wherever it crossed a wood.
##
## `TerrainGrid.GROUND_DETAIL_ORDER` is the ranking, bottom-up, and
## `TerrainGrid._order_ground_detail()` puts the overlays in it: a trail is
## trodden ground and a tree grows through it, so the canopies paint last among
## the ground art and always cover the path graphics. The entities and their
## shadows still ride their own bands above the crown, which is what keeps a
## golfer walking past a wood visible (see
## `tests/unit/golfers/test_golfer_draw_order.gd`).

## The band the course surface and the detail painted on it share.
const GROUND_BAND := 1

var grid: TerrainGrid


func before_each() -> void:
	super()
	grid = make_grid(8, 8)
	fill_grid(grid, TerrainTypes.Type.ROUGH)


# ---------------------------------------------------------------------------
# The canopies over the trail
# ---------------------------------------------------------------------------

## A tree standing on a tile the walk is laid across is painted over the trail —
## by ranking, not by luck of the order the overlays happened to be built in.
func test_the_trees_paint_over_the_walking_trail() -> void:
	var trees := grid.get_node_or_null("TreeOverlay") as CanvasItem
	var trail := grid.get_node_or_null("WalkingPathOverlay") as CanvasItem
	assert_not_null(trees, "the grid paints the woodland sprites")
	assert_not_null(trail, "the grid paints the walking trail")
	assert_gt(_effective_z(trees), GROUND_BAND, "standing trees draw above ground detail")
	assert_eq(_effective_z(trail), GROUND_BAND, "so is a trail")
	assert_gt(trees.get_index(), trail.get_index(),
			"and the trees are drawn after it, so a ribbon never crosses a trunk")


## The whole ground band follows the declared ranking, flowers and trail below.
func test_the_ground_detail_paints_in_the_declared_order() -> void:
	var expected: Array = []
	for overlay_name in TerrainGrid.GROUND_DETAIL_ORDER:
		expected.append(overlay_name)
	var painted: Array = []
	for child in grid.get_children():
		if child is CanvasItem and child.name in expected:
			painted.append(str(child.name))
	assert_eq(painted, expected, "the grid lays the ground overlays out bottom-up, as it ranks them")


## The ranking is applied, not merely intended: put the wood back under the walk
## the way the grid once built it, and the grid ranks the band again.
func test_the_grid_re_ranks_the_ground_band_when_it_is_shuffled() -> void:
	var trees := grid.get_node("TreeOverlay") as CanvasItem
	var trail := grid.get_node("WalkingPathOverlay") as CanvasItem
	grid.move_child(trees, 0)  # The old arrangement: the wood painted first.
	assert_lt(trees.get_index(), trail.get_index(), "the trail covers the trees")
	grid._order_ground_detail()
	assert_gt(trees.get_index(), trail.get_index(), "the trees are ranked over the trail again")
	assert_eq(grid.get_node("CourseSurface").get_index(), 0,
			"and what is not on the list keeps its place under the whole band")


# ---------------------------------------------------------------------------
# What the ranking leaves alone
# ---------------------------------------------------------------------------

## Standing trees must compete with people and buildings in the same band.
func test_the_trees_share_entity_depth_sorting() -> void:
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	var entities := make_entity_layer(grid)
	assert_eq(_effective_z(trees), _effective_z(entities))
	assert_true(trees.y_sort_enabled)
	assert_true(entities.y_sort_enabled)

func test_each_tree_has_its_own_ground_sort_anchor() -> void:
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	var back := Vector2i(2, 2)
	var front := Vector2i(3, 4)
	grid.set_tile(back, TerrainTypes.Type.PINE)
	grid.set_tile(front, TerrainTypes.Type.OAK)
	trees._sync_visuals()
	assert_eq(trees._visuals.size(), 2)
	assert_eq(trees._visuals[back].position, grid.grid_to_screen_center(back))
	assert_eq(trees._visuals[front].position, grid.grid_to_screen_center(front))
	assert_lt(trees._visuals[back].position.y, trees._visuals[front].position.y)
	grid.set_tile(back, TerrainTypes.Type.ROUGH)
	trees._sync_visuals()
	assert_false(trees._visuals.has(back), "painting over a tree removes its sorted sprite")
	assert_eq(trees._visuals.size(), 1)


## A trail across a wood keeps both halves of its art: the walk is not erased by
## the tree standing in it, only covered where the sprite rises over it.
func test_a_trail_through_a_wood_draws_the_walk_and_the_tree() -> void:
	var tile := Vector2i(3, 3)
	assert_true(grid.set_walking_path(tile, true), "rough hosts a trail")
	grid.set_tile(tile, TerrainTypes.Type.PINE)
	assert_true(grid.has_walking_path(tile),
			"and so does woodland: a tree can grow in a trodden walk")
	var trees := grid.get_node("TreeOverlay") as TreeOverlay
	var trail := grid.get_node("WalkingPathOverlay") as WalkingPathOverlay
	assert_true(trees._tree_tiles.has(tile), "the overlay draws the pine standing there")
	assert_true(trail._path_tiles.has(tile), "and the ribbon it grew through")
	assert_gte(trail.tile_draw_commands(tile, false, false).size(), 2,
			"the trail is still painted on the tile, under the trunk")


## The z an item is actually drawn at: its own band, plus the bands of the
## relative parents above it, the way Godot resolves it.
func _effective_z(item: CanvasItem) -> int:
	var z := 0
	var node: Node = item
	while node is CanvasItem:
		var canvas_item := node as CanvasItem
		if canvas_item.z_as_relative:
			z += canvas_item.z_index
		else:
			z = canvas_item.z_index
		node = canvas_item.get_parent()
	return z
