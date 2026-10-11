extends GameTest
## Where a golfer is drawn, next to the ground art it stands on.
##
## The terrain grid paints the course surface at z 0 (turf, sand and the cart
## paths) and the detail it lays on that surface - the walking trail, trees,
## water, flowers - at z 1. A golfer used to sit at z 0 as well, the band of the
## opaque surface, so a golfer on a trail was drawn UNDER the trail's ribbon (and
## their shadow and tier ring under the surface itself, where they were never
## seen at all). Golfers paint in the entity band now: z 2 on the scene root
## (docs/architecture.md, Draw Order), with the shadow, the rings and the name
## label as offsets of that one band.
##
## A band is only a number, so these tests hold the arrangement the game builds:
## the grid laid down first, the entity containers after it. Items sharing a band
## are drawn in tree order, which is why the surface can be level with a golfer's
## tier ring and still paint before it.

const GOLFER_SCENE := preload("res://scenes/entities/golfer.tscn")

## The band the entities (golfers, buildings, decorations) are drawn in.
const ENTITY_BAND := 2

## The band the course surface and the overlays on it are drawn in.
const GROUND_BAND := 1

## Stands in for Main: the grid first, the entity container after it, exactly as
## main.tscn orders them.
var world: Node2D

var grid: TerrainGrid
var golfer: Golfer
var sprite: CanvasItem

func before_each() -> void:
	super()
	world = Node2D.new()
	world.name = "World"
	add_child_autofree(world)

	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	world.add_child(grid)

	var entities := Node2D.new()
	entities.name = "Entities"
	world.add_child(entities)
	var golfers := Node2D.new()
	golfers.name = "Golfers"
	golfers.y_sort_enabled = true
	entities.add_child(golfers)

	golfer = GOLFER_SCENE.instantiate() as Golfer
	golfers.add_child(golfer)
	golfer.set_process(false)
	golfer.set_physics_process(false)
	await process_frames(1)

	# The sprite the golfer is actually drawn with: the skin's AnimatedSprite2D
	# when they wear one, the polygon Visual underneath otherwise.
	sprite = golfer.sprite_node() as CanvasItem
	if sprite == null:
		sprite = golfer.visual as CanvasItem


# ---------------------------------------------------------------------------
# The bands
# ---------------------------------------------------------------------------

func test_the_golfer_is_drawn_in_the_entity_band() -> void:
	assert_eq(_effective_z(golfer), ENTITY_BAND,
			"a golfer belongs with the other entities, not with the ground (z %d)" % _effective_z(golfer))
	assert_true(golfer.z_as_relative,
			"the shadow, the rings and the label are offsets of that one band")

func test_the_walking_trail_is_ground_art() -> void:
	var trail := grid.get_node_or_null("WalkingPathOverlay") as CanvasItem
	assert_not_null(trail, "the grid paints the walking trail")
	assert_eq(_effective_z(trail), GROUND_BAND,
			"the trail is laid on the surface, not over the players on it")


# ---------------------------------------------------------------------------
# The golfer over the ground art
# ---------------------------------------------------------------------------

func test_the_golfer_is_drawn_over_every_overlay_on_the_ground() -> void:
	var ground_items := _ground_band_items()
	assert_gt(ground_items.size(), 1, "the grid paints ground art under the golfers")
	var trail_seen := false
	for item in ground_items:
		if item.name == "WalkingPathOverlay":
			trail_seen = true
		assert_gt(_effective_z(sprite), _effective_z(item),
				"%s paints at z %d: the golfer's sprite must draw over it"
						% [item.name, _effective_z(item)])
	assert_true(trail_seen, "the walking trail is one of the overlays checked")

func test_the_golfers_shadow_lies_on_the_ground_art() -> void:
	# The Expression node owns the Visual subtree once the golfer is ready, so
	# the shadow is looked up under the visual reference, not a fixed path.
	var shadow := golfer.visual.get_node_or_null("Shadow") as CanvasItem
	assert_not_null(shadow, "the golfer casts a shadow")
	var trail := grid.get_node_or_null("WalkingPathOverlay") as CanvasItem
	assert_gte(_effective_z(shadow), _effective_z(trail),
			"a shadow on the trail still paints after it (same band, later tree order)")
	assert_gt(_effective_z(sprite), _effective_z(shadow),
			"the shadow stays under the golfer who casts it")

func test_no_part_of_the_golfer_is_buried_under_the_course_surface() -> void:
	var surface := grid.get_node_or_null("CourseSurface") as CanvasItem
	assert_not_null(surface, "the grid paints the course surface")
	for item in _golfer_items():
		assert_gte(_effective_z(item), _effective_z(surface),
				"%s draws at z %d, behind the opaque surface (z %d)"
						% [item.name, _effective_z(item), _effective_z(surface)])


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

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

## The canvas items the grid paints on the ground: the surface and its overlays,
## everything down at the surface's own band.
func _ground_band_items() -> Array:
	var items: Array = []
	for child in grid.get_children():
		if child is CanvasItem and _effective_z(child) <= GROUND_BAND:
			items.append(child)
	return items

## Every canvas item the golfer draws with - the sprite, the polygon art, the
## shadow, the rings, the labels.
func _golfer_items() -> Array:
	var items: Array = []
	_collect_canvas_items(golfer, items)
	return items

func _collect_canvas_items(node: Node, items: Array) -> void:
	for child in node.get_children():
		if child is CanvasItem:
			items.append(child)
		_collect_canvas_items(child, items)
