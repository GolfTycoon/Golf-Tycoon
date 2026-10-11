extends GameTest
## Path furniture: benches and other improvements set beside a walk stand off its
## centre line, on the side clear of water and the map edge, and keep their
## anchor when the walk is repainted.

var grid: TerrainGrid
var entities: EntityLayer
var registry: Dictionary

func before_each() -> void:
	super()
	grid = TerrainGrid.new()
	grid.grid_width = 8
	grid.grid_height = 8
	add_child_autofree(grid)
	for x in range(8):
		for y in range(8):
			grid.set_tile(Vector2i(x, y), TerrainTypes.Type.GRASS)
	entities = EntityLayer.new()
	entities.map_seed = 1234
	add_child_autofree(entities)
	entities.set_terrain_grid(grid)
	registry = JSON.parse_string(FileAccess.get_file_as_string("res://data/decorations.json"))["decorations"]

## Lay the walk a piece of path furniture stands beside: the ground the Path
## improvement accepts, with the trail on it. Furniture reads the trail layer, not
## the terrain, so the ground underneath is whatever the walk was cut through.
func _lay_walk(tiles: Array) -> void:
	for tile in tiles:
		grid.set_tile(tile, TerrainTypes.Type.ROUGH)
		grid.set_walking_path(tile, true)

func _row(y: int) -> Array:
	var tiles: Array = []
	for x in range(8):
		tiles.append(Vector2i(x, y))
	return tiles

func _column(x: int) -> Array:
	var tiles: Array = []
	for y in range(8):
		tiles.append(Vector2i(x, y))
	return tiles

func test_horizontal_and_vertical_walks_keep_furniture_off_center() -> void:
	_lay_walk(_row(3))
	var bench := entities.place_decoration("park_bench", Vector2i(4, 3), registry)
	assert_eq(bench.get_node("Visual").position, Vector2(0, -10))
	assert_eq(bench.get_node("Visual/PathFurniture").facing, Vector2i.DOWN)
	_lay_walk(_column(1))
	var washer := entities.place_decoration("ball_washer", Vector2i(1, 5), registry)
	assert_eq(washer.get_node("Visual").position, Vector2(-23, 0))
	assert_eq(washer.get_node("Visual/PathFurniture").facing, Vector2i.RIGHT)

func test_edge_choice_avoids_water_and_map_boundary() -> void:
	_lay_walk([Vector2i.ZERO])
	grid.set_tile(Vector2i(1, 0), TerrainTypes.Type.WATER)
	var layout := PathFurniture.layout(grid, Vector2i.ZERO, "park_bench")
	assert_eq(layout.offset, Vector2(0, 10), "Only the southern edge has a safe verge")
	assert_eq(layout.facing, Vector2i.UP)

func test_repainting_and_quiet_refresh_realign_existing_furniture_without_moving_its_tile() -> void:
	_lay_walk(_row(3))
	var pos := Vector2i(4, 3)
	var bench := entities.place_decoration("park_bench", pos, registry)
	var saved := bench.get_decoration_info()
	_lay_walk([pos + Vector2i.UP])
	await process_frames(1)
	assert_eq(bench.get_node("Visual").position, Vector2(0, 10))
	assert_eq(bench.get_node("Visual/PathFurniture").facing, Vector2i.UP)
	grid.begin_batch()
	grid.set_tile(pos + Vector2i.UP, TerrainTypes.Type.GRASS)
	grid.end_batch_quiet()
	grid.refresh_all_overlays()
	await process_frames(1)
	assert_eq(bench.get_node("Visual").position, Vector2(0, -10))
	assert_eq(bench.get_decoration_info(), saved)
	assert_eq(entities.get_decoration_at(pos), bench, "Selection/removal still resolves the original tile")

func test_plazas_and_large_decorations_retain_their_anchor() -> void:
	var plaza: Array = []
	for x in range(2, 5):
		for y in range(2, 5):
			plaza.append(Vector2i(x, y))
	_lay_walk(plaza)
	assert_eq(PathFurniture.layout(grid, Vector2i(3, 3), "park_bench").offset, Vector2.ZERO)
	assert_eq(PathFurniture.layout(grid, Vector2i(3, 2), "fountain").offset, Vector2.ZERO)
	assert_eq(PathFurniture.layout(grid, Vector2i(3, 2), "golfer_statue").offset, Vector2.ZERO)

func test_sprite_feet_and_animated_details_use_the_same_anchor() -> void:
	for type in ["fountain", "golfer_statue", "sundial"]:
		var dec := entities.place_decoration(type, Vector2i(3, 3), registry)
		var sprite: Sprite2D = dec.get_node("Visual/DecorationSprite")
		var bottom := sprite.texture.get_image().get_used_rect().end.y
		assert_almost_eq(sprite.position.y + bottom - sprite.texture.get_height() * 0.5, 0.0, 0.01, "%s base meets its anchor" % type)
		if type == "fountain":
			assert_eq(dec.get_node("Visual/Atmosphere").position.y, -5.0)
		entities.remove_decoration(Vector2i(3, 3))
		await process_frames(1)
