extends GameTest
## WaterOverlay keeps a sparse index of water tiles so repeated redraws can
## skip empty terrain, while load notifications rebuild that index after the
## grid is bulk-deserialized.

var grid: TerrainGrid
var overlay: WaterOverlay

func before_each() -> void:
	super()
	grid = TerrainGrid.new()
	grid.grid_width = 16
	grid.grid_height = 16
	add_child_autofree(grid)
	await process_frames(1)
	overlay = WaterOverlay.new()
	grid.add_child(overlay)
	overlay.initialize(grid)

func test_water_index_tracks_incremental_tile_changes() -> void:
	var pos := Vector2i(7, 7)
	grid.set_tile(pos, TerrainTypes.Type.WATER)
	assert_true(overlay._water_positions.has(pos))
	grid.set_tile(pos, TerrainTypes.Type.FAIRWAY)
	assert_false(overlay._water_positions.has(pos))

func test_water_index_is_rebuilt_after_a_successful_load() -> void:
	var pos := Vector2i(5, 6)
	grid.deserialize({"5,6": TerrainTypes.Type.WATER})
	assert_false(overlay._water_positions.has(pos),
		"bulk deserialization does not emit per-tile overlay signals")
	EventBus.load_completed.emit(true)
	assert_true(overlay._water_positions.has(pos),
		"the load signal rebuilds the sparse water index")
