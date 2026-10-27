extends Node2D
class_name EntityLayer
## EntityLayer - Manages all placed buildings and decorations on the course
##
## Woodland is not an entity: every tree is a Course Terrain tile the surface
## and the TreeOverlay draw (see TerrainTypes.is_tree), laid and replaced by
## painting like Rocks or Wild Flowers. A save from before that carries a
## "trees" block, which deserialize turns back into painted tiles.

var buildings: Dictionary = {}     # key: Vector2i (grid_pos), value: Building node
var decorations: Dictionary = {}   # key: Vector2i (grid_pos), value: Decoration node

var terrain_grid: TerrainGrid
var building_registry: Dictionary = {}  # Can accept either Node or Dictionary
var decoration_registry: Dictionary = {}  # Loaded from data/decorations.json
## Ground hidden by each building, including the *shared vertex* heights.
## Keys are building origins; each value has `tiles` and `vertices` maps.
## Neighbouring foundations remember the same original height for a shared
## vertex, which is restored only when the last building using it leaves.
var _building_original_terrain: Dictionary = {}

const FOUNDATION_CONFLICT_ERROR := "Nearby buildings stand at different elevations."

## Map seed for deterministic prop variations
## Set once at game start or load for consistent visual results
var map_seed: int = 0

signal building_placed(building: Building, cost: int)
signal decoration_placed(decoration: Decoration, cost: int)
signal building_removed(grid_pos: Vector2i)
## The building changed address: its dictionary key and its node both moved.
signal building_moved(building: Building, from_pos: Vector2i, to_pos: Vector2i)
signal decoration_removed(grid_pos: Vector2i)
signal building_selected(building: Building)

@onready var buildings_container = Node2D.new()
@onready var decorations_container = Node2D.new()

func _ready() -> void:
	# Relative shadow layers (-2/-1) must remain above the opaque terrain.
	z_index = 2
	y_sort_enabled = true
	buildings_container.name = "Buildings"
	decorations_container.name = "Decorations"

	# Enable Y-sorting for proper isometric depth ordering
	# Objects lower on screen (higher Y) render in front of objects higher on screen
	buildings_container.y_sort_enabled = true
	decorations_container.y_sort_enabled = true

	add_child(buildings_container)
	add_child(decorations_container)

	# Generate a random map seed if not set (new game)
	if map_seed == 0:
		randomize()
		map_seed = randi()
	_apply_map_seed()


func _apply_map_seed() -> void:
	"""Apply the map seed to the prop variation system"""
	PropVariation.set_map_seed(map_seed)


func set_map_seed(seed_value: int) -> void:
	"""Set the map seed and apply it to prop variations"""
	map_seed = seed_value
	_apply_map_seed()

func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid

func set_building_registry(registry) -> void:
	building_registry = registry

func set_decoration_registry(registry: Dictionary) -> void:
	decoration_registry = registry

func place_building(building_type: String, grid_pos: Vector2i, registry,
		saved_foundation: Dictionary = {}) -> Building:
	"""Place a building, or reconstruct one with its saved foundation."""
	if registry == null or (registry is Dictionary and registry.is_empty()):
		push_error("Building registry not set")
		return null

	var building_data
	if registry is Dictionary:
		building_data = registry.get(building_type, {})
	else:
		# Support legacy Node-based registry
		building_data = registry.get_building(building_type) if registry.has_method("get_building") else {}

	if building_data.is_empty():
		push_error("Unknown building type: %s" % building_type)
		return null

	if building_data.get("required", false):
		for existing in buildings.values():
			if existing.building_type == building_type:
				push_error("Cannot place duplicate unique building: %s" % building_type)
				return null

	var dimensions: Array = building_data.get("size", [1, 1])
	var size := Vector2i(int(dimensions[0]), int(dimensions[1]))
	if _would_overlap_building(grid_pos, size.x, size.y):
		push_error("Cannot place building: overlaps with existing building")
		return null
	# A saved foundation already describes the ground at the time of the save.
	# Loading must not repaint or re-level it, even if an old course contains
	# ground that was subsequently changed by another system.
	if saved_foundation.is_empty() and not foundation_placement_error(grid_pos, size).is_empty():
		return null

	var target := foundation_elevation(grid_pos, size) if terrain_grid and saved_foundation.is_empty() else 0
	var building := Building.new()
	building.building_type = building_type
	building.building_data = building_data.duplicate(true)
	building.width = size.x
	building.height = size.y
	building.set_terrain_grid(terrain_grid)
	building.set_position_in_grid(grid_pos)
	buildings_container.add_child(building)
	buildings[grid_pos] = building
	building.building_selected.connect(_on_building_selected)
	building.building_destroyed.connect(_on_building_destroyed)

	if terrain_grid:
		if saved_foundation.is_empty():
			_lay_building_foundation(grid_pos, size, target)
		else:
			_building_original_terrain[grid_pos] = saved_foundation
		# Flattening can change the elevation at the centre of the drawing.
		building.set_position_in_grid(grid_pos)

	building_placed.emit(building, building_data.get("cost", 0))
	return building

func get_building_at(grid_pos: Vector2i) -> Building:
	return buildings.get(grid_pos, null)


## Two neighbouring buildings share their boundary vertices. They must agree
## on a height there, or a new flat foundation between them is impossible.
## This is also used by the placement and clubhouse previews.
func foundation_placement_error(origin: Vector2i, size: Vector2i,
		moving: Building = null) -> String:
	if terrain_grid == null:
		return ""
	if size.x <= 0 or size.y <= 0 or not terrain_grid.is_valid_position(origin) \
			or not terrain_grid.is_valid_position(origin + size - Vector2i.ONE):
		return "The entire footprint must fit inside the course."
	if _neighbour_foundation_height(origin, size, moving) == -2:
		return FOUNDATION_CONFLICT_ERROR
	return ""

## -1 means no neighbour; -2 means neighbours require conflicting heights.
func _neighbour_foundation_height(origin: Vector2i, size: Vector2i,
		moving: Building = null) -> int:
	if terrain_grid == null:
		return -1
	var level := -1
	for building in buildings.values():
		if building == moving:
			continue
		var other_origin: Vector2i = building.grid_position
		var other_end := other_origin + Vector2i(building.width, building.height)
		var first := Vector2i(maxi(origin.x, other_origin.x), maxi(origin.y, other_origin.y))
		var last := Vector2i(mini(origin.x + size.x, other_end.x),
				mini(origin.y + size.y, other_end.y))
		if first.x > last.x or first.y > last.y:
			continue
		for x in range(first.x, last.x + 1):
			for y in range(first.y, last.y + 1):
				var height := terrain_grid.get_vertex_elevation(Vector2i(x, y))
				if level >= 0 and height != level:
					return -2
				level = height
	return level

## A legacy save can contain buildings placed before flat foundations existed.
## If the next saved building bridges different levels, rejecting it would
## silently lose it. Level the connected cluster once during migration, while
## retaining every already-captured original vertex for later restoration.
func _reconcile_legacy_foundations(origin: Vector2i, size: Vector2i) -> void:
	if terrain_grid == null:
		return
	var pending: Array[Rect2i] = [Rect2i(origin, size)]
	var connected: Array[Building] = []
	while not pending.is_empty():
		var plot: Rect2i = pending.pop_back()
		for building in buildings.values():
			if building in connected:
				continue
			var other := Rect2i(building.grid_position, Vector2i(building.width, building.height))
			if not _footprints_share_vertices(plot, other):
				continue
			connected.append(building)
			pending.append(other)
	if connected.is_empty():
		return
	var target := terrain_grid.get_elevation(connected[0].grid_position)
	for building in connected:
		var building_size := Vector2i(building.width, building.height)
		for vertex in _foundation_vertices(building.grid_position, building_size):
			terrain_grid.set_vertex_elevation(vertex, target)
		building.set_position_in_grid(building.grid_position)

static func _footprints_share_vertices(first: Rect2i, second: Rect2i) -> bool:
	return first.position.x <= second.end.x and first.end.x >= second.position.x \
			and first.position.y <= second.end.y and first.end.y >= second.position.y

## The level a footprint will take. A move can overlap its current footprint:
## preview the original corner heights that will be restored before placement,
## except for vertices still pinned by another building.
func foundation_elevation(origin: Vector2i, size: Vector2i, moving: Building = null) -> int:
	if terrain_grid == null or not terrain_grid.is_valid_position(origin):
		return TerrainGrid.BASE_ELEVATION
	var neighbour := _neighbour_foundation_height(origin, size, moving)
	if neighbour >= 0:
		return neighbour
	if is_instance_valid(moving) and buildings.get(moving.grid_position) == moving \
			and _building_original_terrain.has(moving.grid_position):
		var old_vertices: Dictionary = _building_original_terrain[moving.grid_position].get("vertices", {})
		var total := 0
		for vertex in terrain_grid.vertices_of_tile(origin):
			var height := terrain_grid.get_vertex_elevation(vertex)
			if old_vertices.has(vertex) and not _foundation_vertex_is_shared(vertex, moving.grid_position):
				height = int(old_vertices[vertex])
			total += height
		return roundi(float(total) / 4.0)
	return terrain_grid.get_elevation(origin)

func _foundation_vertices(origin: Vector2i, size: Vector2i) -> Array[Vector2i]:
	var vertices: Array[Vector2i] = []
	for x in range(size.x + 1):
		for y in range(size.y + 1):
			vertices.append(origin + Vector2i(x, y))
	return vertices

## Record the actual corner heights, not the rounded average of each tile:
## corners are shared with neighbouring tiles and cannot be recovered from
## tile averages. Building work is not a separate terrain undo action.
func _lay_building_foundation(origin: Vector2i, size: Vector2i, target: int) -> void:
	var tiles: Dictionary = {}
	var vertices: Dictionary = {}
	for x in range(size.x):
		for y in range(size.y):
			var tile := origin + Vector2i(x, y)
			tiles[tile] = {
				"type": terrain_grid.get_tile(tile),
				"player_placed": terrain_grid._player_placed_tiles.has(tile),
				"walking_path": terrain_grid.has_walking_path(tile),
				"cup": terrain_grid.has_cup_tile(tile),
			}
	for vertex in _foundation_vertices(origin, size):
		var original := terrain_grid.get_vertex_elevation(vertex)
		for other in _building_original_terrain.values():
			var other_vertices: Dictionary = other.get("vertices", {})
			if other_vertices.has(vertex):
				original = int(other_vertices[vertex])
				break
		vertices[vertex] = original

	_building_original_terrain[origin] = {"tiles": tiles, "vertices": vertices}
	for tile in tiles:
		terrain_grid.set_tile_natural(tile, TerrainTypes.Type.ROUGH, false)
	for vertex in vertices:
		terrain_grid.set_vertex_elevation(vertex, target)

func _restore_building_terrain(building_pos: Vector2i) -> void:
	if terrain_grid == null or not _building_original_terrain.has(building_pos):
		return
	var foundation: Dictionary = _building_original_terrain[building_pos]
	for tile in foundation.get("tiles", {}):
		var original: Dictionary = foundation["tiles"][tile]
		terrain_grid.set_tile_natural(tile, int(original["type"]), false)
		if bool(original.get("player_placed", false)):
			terrain_grid._player_placed_tiles[tile] = true
		else:
			terrain_grid._player_placed_tiles.erase(tile)
		if bool(original.get("cup", false)):
			terrain_grid.add_cup_tile(tile)
		else:
			terrain_grid.remove_cup_tile(tile)
		terrain_grid.set_walking_path(tile, bool(original.get("walking_path", false)))
	for vertex in foundation.get("vertices", {}):
		if not _foundation_vertex_is_shared(vertex, building_pos):
			terrain_grid.set_vertex_elevation(vertex, int(foundation["vertices"][vertex]))

func _foundation_vertex_is_shared(vertex: Vector2i, excluding: Vector2i) -> bool:
	for other_pos in _building_original_terrain:
		if other_pos == excluding or not buildings.has(other_pos):
			continue
		if _building_original_terrain[other_pos].get("vertices", {}).has(vertex):
			return true
	return false

func get_buildings_in_area(top_left: Vector2i, bottom_right: Vector2i) -> Array:
	"""Get all buildings within the specified area"""
	var result: Array = []
	for pos in buildings.keys():
		if pos.x >= top_left.x and pos.x <= bottom_right.x and \
		   pos.y >= top_left.y and pos.y <= bottom_right.y:
			result.append(buildings[pos])
	return result

func remove_building(grid_pos: Vector2i, force: bool = false) -> void:
	var building = buildings.get(grid_pos, null)
	if building == null:
		# A demolition click can land anywhere on a multi-tile facility.
		building = get_building_containing(grid_pos)
		if building == null:
			return
		grid_pos = building.grid_position
	if not force and building.is_required():
		return

	_restore_building_terrain(grid_pos)
	building.destroy(force)
	buildings.erase(grid_pos)
	_building_original_terrain.erase(grid_pos)
	building_removed.emit(grid_pos)

## Move a building without replacing its node, upgrades or history. Restore
## the old ground before capturing the new footprint, so overlapping moves
## remember the actual terrain rather than the building's temporary lawn.
func move_building(building: Building, new_pos: Vector2i) -> bool:
	if not is_instance_valid(building):
		return false
	var old_pos: Vector2i = building.grid_position
	if old_pos == new_pos or buildings.get(old_pos) != building:
		return false
	var size := Vector2i(building.width, building.height)
	if _would_overlap_building(new_pos, size.x, size.y, building) \
			or not foundation_placement_error(new_pos, size, building).is_empty():
		return false

	_restore_building_terrain(old_pos)
	_building_original_terrain.erase(old_pos)
	buildings.erase(old_pos)
	if terrain_grid:
		_lay_building_foundation(new_pos, size, foundation_elevation(new_pos, size))
	building.set_position_in_grid(new_pos)
	buildings[new_pos] = building
	building_moved.emit(building, old_pos, new_pos)
	return true

func place_decoration(dec_type: String, grid_pos: Vector2i, dec_registry: Dictionary) -> Decoration:
	"""Place a decoration at the specified grid position"""
	var dec_data = dec_registry.get(dec_type, {})
	if dec_data.is_empty():
		push_error("Unknown decoration type: %s" % dec_type)
		return null

	var sz = dec_data.get("size", [1, 1])
	var dec_width = int(sz[0])
	var dec_height = int(sz[1])

	# Check for overlap with existing entities (buildings, decorations)
	if _would_overlap_building(grid_pos, dec_width, dec_height):
		push_error("Cannot place decoration: overlaps with existing building")
		return null
	if _would_overlap_decoration(grid_pos, dec_width, dec_height):
		push_error("Cannot place decoration: overlaps with existing decoration")
		return null

	var decoration = Decoration.new()
	decoration.set_terrain_grid(terrain_grid)
	decoration.set_decoration_type(dec_type, dec_data)
	decoration.set_position_in_grid(grid_pos)

	decorations_container.add_child(decoration)

	# Store by grid position (anchor tile)
	decorations[grid_pos] = decoration

	decoration.decoration_selected.connect(_on_decoration_selected)
	decoration.decoration_destroyed.connect(_on_decoration_destroyed)

	decoration_placed.emit(decoration, dec_data.get("cost", 0))
	EventBus.decoration_placed.emit(dec_type, grid_pos)
	return decoration

func remove_decoration(grid_pos: Vector2i) -> void:
	var decoration = decorations.get(grid_pos, null)
	if decoration:
		decoration.destroy()
		decorations.erase(grid_pos)
		decoration_removed.emit(grid_pos)
		EventBus.decoration_removed.emit(grid_pos)

func get_decoration_at(grid_pos: Vector2i) -> Decoration:
	"""Get decoration at position, checking both anchor tiles and footprints"""
	# Direct lookup first
	if decorations.has(grid_pos):
		return decorations[grid_pos]
	# Check if grid_pos falls within any multi-tile decoration's footprint
	for dec in decorations.values():
		if dec.size.x > 1 or dec.size.y > 1:
			var footprint = dec.get_footprint()
			if grid_pos in footprint:
				return dec
	return null

func get_all_decorations() -> Array:
	return decorations.values()

func get_decorations_in_area(top_left: Vector2i, bottom_right: Vector2i) -> Array:
	"""Get all decorations within the specified area (checks footprint for multi-tile)"""
	var result: Array = []
	for dec in decorations.values():
		# Check if any tile in footprint is within the area
		var in_area = false
		for tile_pos in dec.get_footprint():
			if tile_pos.x >= top_left.x and tile_pos.x <= bottom_right.x and \
			   tile_pos.y >= top_left.y and tile_pos.y <= bottom_right.y:
				in_area = true
				break
		if in_area:
			result.append(dec)
	return result

func _would_overlap_decoration(new_pos: Vector2i, new_width: int, new_height: int) -> bool:
	"""Check if a new entity would overlap with any existing decoration"""
	for existing in decorations.values():
		var ex_pos = existing.grid_position
		var ex_width = existing.size.x
		var ex_height = existing.size.y

		var new_right = new_pos.x + new_width
		var new_bottom = new_pos.y + new_height
		var ex_right = ex_pos.x + ex_width
		var ex_bottom = ex_pos.y + ex_height

		if new_pos.x < ex_right and new_right > ex_pos.x and new_pos.y < ex_bottom and new_bottom > ex_pos.y:
			return true
	return false

func is_tile_occupied_by_decoration(grid_pos: Vector2i) -> bool:
	"""Check if a tile is occupied by any decoration (including multi-tile)"""
	return get_decoration_at(grid_pos) != null

func get_all_buildings() -> Array:
	return buildings.values()

func _would_overlap_building(new_pos: Vector2i, new_width: int, new_height: int,
		ignore: Building = null) -> bool:
	"""Check if a new building would overlap with any existing building"""
	for existing in buildings.values():
		if existing == ignore:
			continue
		var ex_pos = existing.grid_position
		var ex_width = existing.width
		var ex_height = existing.height

		# Check if rectangles overlap
		var new_right = new_pos.x + new_width
		var new_bottom = new_pos.y + new_height
		var ex_right = ex_pos.x + ex_width
		var ex_bottom = ex_pos.y + ex_height

		if new_pos.x < ex_right and new_right > ex_pos.x and new_pos.y < ex_bottom and new_bottom > ex_pos.y:
			return true

	return false

func has_building_of_type(building_type: String) -> bool:
	## Check if a building of the specified type already exists
	for existing in buildings.values():
		if existing.building_type == building_type:
			return true
	return false

func is_tile_occupied_by_building(grid_pos: Vector2i) -> bool:
	## Check if a tile is occupied by any building (including multi-tile buildings)
	return get_building_containing(grid_pos) != null

func get_building_containing(grid_pos: Vector2i) -> Building:
	## Get the building whose footprint covers this tile (multi-tile aware).
	## Buildings are keyed by their top-left placement tile, so demolition from
	## any tile of the facility looks the footprint up like this.
	for building in buildings.values():
		var b_pos = building.grid_position
		if grid_pos.x >= b_pos.x and grid_pos.x < b_pos.x + building.width and \
		   grid_pos.y >= b_pos.y and grid_pos.y < b_pos.y + building.height:
			return building
	return null

func serialize() -> Dictionary:
	var data: Dictionary = {
		"map_seed": map_seed,
		"buildings": {},
		"decorations": {},
	}

	for pos in buildings:
		var info: Dictionary = buildings[pos].get_building_info()
		if _building_original_terrain.has(pos):
			info["foundation"] = _serialize_foundation(_building_original_terrain[pos])
		data["buildings"]["%d,%d" % [pos.x, pos.y]] = info

	for pos in decorations:
		data["decorations"]["%d,%d" % [pos.x, pos.y]] = decorations[pos].get_decoration_info()

	return data

## JSON uses string keys, so encode both maps explicitly instead of relying on
## Vector2i's textual representation. Older saves simply have no foundation.
func _serialize_foundation(foundation: Dictionary) -> Dictionary:
	var result := {"tiles": {}, "vertices": {}}
	for tile in foundation.get("tiles", {}):
		result["tiles"]["%d,%d" % [tile.x, tile.y]] = foundation["tiles"][tile].duplicate(true)
	for vertex in foundation.get("vertices", {}):
		result["vertices"]["%d,%d" % [vertex.x, vertex.y]] = foundation["vertices"][vertex]
	return result

## Only accept a complete snapshot for this footprint. If a save is old or
## malformed, place normally and snapshot the ground that is actually there.
func _deserialize_foundation(saved: Variant, origin: Vector2i, size: Vector2i) -> Dictionary:
	if terrain_grid == null or not saved is Dictionary:
		return {}
	var saved_tiles: Variant = saved.get("tiles", {})
	var saved_vertices: Variant = saved.get("vertices", {})
	if not saved_tiles is Dictionary or not saved_vertices is Dictionary:
		return {}
	var tiles: Dictionary = {}
	var vertices: Dictionary = {}
	for x in range(size.x):
		for y in range(size.y):
			var tile := origin + Vector2i(x, y)
			var key := "%d,%d" % [tile.x, tile.y]
			var original: Variant = saved_tiles.get(key)
			if not terrain_grid.is_valid_position(tile) or not original is Dictionary \
					or not original.has("type") or not (original["type"] is int or original["type"] is float):
				return {}
			tiles[tile] = {
				"type": int(original["type"]),
				"player_placed": bool(original.get("player_placed", false)),
				"walking_path": bool(original.get("walking_path", false)),
				"cup": bool(original.get("cup", false)),
			}
	for vertex in _foundation_vertices(origin, size):
		var key := "%d,%d" % [vertex.x, vertex.y]
		var height: Variant = saved_vertices.get(key)
		if not terrain_grid.is_valid_vertex(vertex) or not (height is int or height is float):
			return {}
		vertices[vertex] = clampi(int(height), TerrainGrid.MIN_ELEVATION, TerrainGrid.MAX_ELEVATION)
	return {"tiles": tiles, "vertices": vertices}

func clear_all() -> void:
	"""Remove all entities from the layer."""
	for pos in buildings.keys():
		# force: teardown clears the layer regardless of what is standing on
		# it. clear_all means "empty", not "demolish what the rules allow".
		buildings[pos].destroy(true)
	buildings.clear()
	_building_original_terrain.clear()
	for pos in decorations.keys():
		decorations[pos].destroy()
	decorations.clear()

func deserialize(data: Dictionary) -> void:
	"""Reconstruct entities from saved data."""
	clear_all()

	# Restore map seed for consistent prop variations
	if data.has("map_seed"):
		set_map_seed(data["map_seed"])

	# Ground an entity stamped over, remembered by an old save. It is only
	# needed while the legacy blocks below are read, and never written again.
	var original_terrain: Dictionary = {}
	if data.has("original_terrain"):
		for key in data["original_terrain"]:
			var parts = key.split(",")
			if parts.size() == 2:
				original_terrain[Vector2i(int(parts[0]), int(parts[1]))] = int(data["original_terrain"][key])

	# Trees used to be sprite entities standing on a Trees tile; now every
	# species is a Course Terrain tile of its own. A save from before the change
	# still carries a "trees" block, and its wood is worth keeping: each planted
	# tree becomes the tile of its species, painted where it stood.
	if data.has("trees"):
		for key in data["trees"]:
			var parts = key.split(",")
			if parts.size() != 2:
				continue
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			var saved = data["trees"][key]
			var species := "oak"
			if saved is Dictionary:
				species = str(saved.get("type", saved.get("tree_type", "oak")))
			if terrain_grid:
				terrain_grid.set_tile_natural(pos, TerrainTypes.tree_tile_for_species(species))

	if data.has("buildings"):
		for key in data["buildings"]:
			var parts = key.split(",")
			if parts.size() == 2:
				var pos = Vector2i(int(parts[0]), int(parts[1]))
				var building_info = data["buildings"][key]
				var building_type = building_info.get("building_type", "") if building_info is Dictionary else ""
				if building_type.is_empty():
					building_type = building_info.get("type", "") if building_info is Dictionary else ""
				if not building_type.is_empty():
					var building_data: Dictionary = building_registry.get(building_type, {})
					var dimensions: Array = building_data.get("size", [1, 1])
					var size := Vector2i(int(dimensions[0]), int(dimensions[1]))
					var foundation := _deserialize_foundation(building_info.get("foundation", {}), pos, size)
					if foundation.is_empty() and not _would_overlap_building(pos, size.x, size.y) \
							and foundation_placement_error(pos, size) == FOUNDATION_CONFLICT_ERROR:
						_reconcile_legacy_foundations(pos, size)
					var building = place_building(building_type, pos, building_registry, foundation)
					if building and building_info is Dictionary:
						building.restore_from_info(building_info)

	# Boulders were once sprite entities placed on the course; they are Course
	# Terrain paint now (Small Boulders / Large Boulders). A save from before
	# that change still carries a "rocks" block, and dropping the boulder must
	# not leave its stamp behind: the tile goes back to the ground the boulder
	# stood on. Painted Rocks ground stays Rocks, because that is what it was.
	if data.has("rocks"):
		for key in data["rocks"]:
			var parts = key.split(",")
			if parts.size() != 2:
				continue
			var pos = Vector2i(int(parts[0]), int(parts[1]))
			var original := int(original_terrain.get(pos, -1))
			if terrain_grid and original >= 0 and not TerrainTypes.is_rocks(original):
				terrain_grid.set_tile(pos, original)

	if data.has("decorations"):
		for key in data["decorations"]:
			var parts = key.split(",")
			if parts.size() == 2:
				var pos = Vector2i(int(parts[0]), int(parts[1]))
				var dec_data_saved = data["decorations"][key]
				var dec_type = ""
				if dec_data_saved is Dictionary:
					dec_type = dec_data_saved.get("type", "")
				if dec_type.is_empty() or not decoration_registry.has(dec_type):
					# A save from before an improvement left the catalogue simply
					# drops it, instead of logging an error per vanished item.
					if not dec_type.is_empty():
						push_warning("Skipping saved decoration not in the catalogue: %s" % dec_type)
					continue
				place_decoration(dec_type, pos, decoration_registry)

func _on_building_selected(building: Building) -> void:
	building_selected.emit(building)

func _on_building_destroyed(_building: Building) -> void:
	pass  # Clean up if needed

func _on_decoration_selected(_decoration: Decoration) -> void:
	pass  # Handle decoration selection if needed

func _on_decoration_destroyed(_decoration: Decoration) -> void:
	pass  # Clean up if needed
