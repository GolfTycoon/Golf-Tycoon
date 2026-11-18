extends Node2D
class_name Decoration
## Decoration - Represents a decorative object on the course (fountain, ball washer, bench, statue, sundial)
## Decorations contribute to the Aesthetics rating in CourseRatingSystem.

var grid_position: Vector2i = Vector2i(0, 0)
var decoration_type: String = ""
var category: String = ""
var size: Vector2i = Vector2i(1, 1)
var cost: int = 0
var daily_upkeep: int = 0
var aesthetics_value: float = 0.0
var decoration_data: Dictionary = {}

var terrain_grid: TerrainGrid
var _layout_refresh_pending := false

## Clips the prop where nearer terrain covers it (see refresh_terrain_occlusion()):
## its art as a billboard standing on its tile, as trees are clipped, and its
## shadows as paint on the ground, as the walking trail is.
const TERRAIN_SPRITE_OCCLUSION: Shader = preload("res://shaders/terrain_sprite_occlusion.gdshader")
const TERRAIN_DECAL_OCCLUSION: Shader = preload("res://shaders/terrain_decal_occlusion.gdshader")
## How near a sculpt must be, in tiles, to move the ground the clip is measured
## on: the prop's own tile and the ground its art's base reaches down onto.
const OCCLUSION_REACH_TILES := 2
## How close, in pixels, the ground found under a shadow's point must be drawn
## to that point for the shadow to lie on it (see shadow_grounds()).
const SHADOW_GROUND_MISS := 0.5
## The tile the prop stands on: its own, or the middle of a larger footprint.
var _anchor_tile: Vector2i = Vector2i.ZERO
## The art's and the shadows' occlusion materials: created the first time the
## course has relief, and only worn while occlusion is on.
var _art_material: ShaderMaterial = null
var _shadow_material: ShaderMaterial = null
var _occlusion_active := false
var _occlusion_refresh_queued := false

## Shadow references for updates when sun changes
var _shadow_refs: Dictionary = {}
var _shadow_config: ShadowRenderer.ShadowConfig = null
## The shadow quality the current polygons were built for, so an unrelated
## graphics change (a rate, the water detail) does not rebuild every prop.
var _shadow_detail_built: int = -1

## Variation data for this decoration instance
var _variation: PropVariation.VariationResult = null

signal decoration_selected(decoration: Decoration)
signal decoration_destroyed(decoration: Decoration)

## Sprite textures for decorations that have pixel art assets
const SPRITE_PATHS: Dictionary = {
	"fountain": "res://assets/sprites/decorations/fountain.png",
	"ball_washer": "res://assets/sprites/decorations/ball_washer.png",
	"park_bench": "res://assets/sprites/decorations/park_bench.png",
	"golfer_statue": "res://assets/sprites/decorations/golfer_statue.png",
	"sundial": "res://assets/sprites/decorations/sundial.png",
}

## Sprite foot anchors, measured from the visible base (not the padded canvas).
const SPRITE_BASE_OFFSETS: Dictionary = {
	"fountain": 25.0, "ball_washer": 20.0, "park_bench": 21.0,
	"golfer_statue": 22.0, "sundial": 20.0,
}

## Visual dimensions for shadow configuration
const DECORATION_VISUALS: Dictionary = {
	"fountain": {"visual_height": 36.0, "base_width": 40.0},
	"ball_washer": {"visual_height": 18.0, "base_width": 10.0},
	"park_bench": {"visual_height": 14.0, "base_width": 22.0},
	"golfer_statue": {"visual_height": 36.0, "base_width": 16.0},
	"sundial": {"visual_height": 24.0, "base_width": 18.0},
}

## Variation parameters per decoration type
const DECORATION_VARIATION: Dictionary = {
	"fountain": {"scale": Vector2(0.95, 1.05), "rotation": Vector2(0.0, 0.0), "hue": Vector2(-0.02, 0.02)},
	"ball_washer": {"scale": Vector2(0.95, 1.05), "rotation": Vector2(-3.0, 3.0), "hue": Vector2(-0.01, 0.01)},
	"park_bench": {"scale": Vector2(0.95, 1.05), "rotation": Vector2(-3.0, 3.0), "hue": Vector2(-0.02, 0.02)},
	"golfer_statue": {"scale": Vector2(0.95, 1.05), "rotation": Vector2(0.0, 0.0), "hue": Vector2(-0.01, 0.01)},
	"sundial": {"scale": Vector2(0.95, 1.05), "rotation": Vector2(-3.0, 3.0), "hue": Vector2(-0.01, 0.01)},
}

## Procedural fallback colors per decoration type
const DECORATION_COLORS: Dictionary = {
	"fountain": Color(0.50, 0.65, 0.80),
	"ball_washer": Color(0.50, 0.50, 0.55),
	"park_bench": Color(0.45, 0.30, 0.18),
	"golfer_statue": Color(0.60, 0.50, 0.30),
	"sundial": Color(0.70, 0.65, 0.55),
}


func _ready() -> void:
	add_to_group("decorations")
	y_sort_enabled = true
	if terrain_grid:
		terrain_grid.tile_changed.connect(_on_ground_changed)
		terrain_grid.vertex_elevation_changed.connect(_on_vertex_elevation_changed)
		terrain_grid.surface_refreshed.connect(_queue_layout_refresh)
		terrain_grid.terrain_occlusion_changed.connect(_on_terrain_occlusion_changed)

	if not decoration_type.is_empty():
		_generate_variation()
		_update_visuals()

	# Connect to sun direction changes if ShadowSystem is available
	if has_node("/root/ShadowSystem"):
		var shadow_system = get_node("/root/ShadowSystem")
		if shadow_system.has_signal("sun_direction_changed"):
			shadow_system.sun_direction_changed.connect(_on_sun_direction_changed)
	# Switching shadow quality on the Display page re-shapes every prop at once;
	# a decoration follows without the course being rebuilt.
	if not PerformanceSettings.profile_changed.is_connected(_on_graphics_settings_changed):
		PerformanceSettings.profile_changed.connect(_on_graphics_settings_changed)


func _exit_tree() -> void:
	if is_instance_valid(terrain_grid):
		if terrain_grid.tile_changed.is_connected(_on_ground_changed):
			terrain_grid.tile_changed.disconnect(_on_ground_changed)
		if terrain_grid.vertex_elevation_changed.is_connected(_on_vertex_elevation_changed):
			terrain_grid.vertex_elevation_changed.disconnect(_on_vertex_elevation_changed)
		if terrain_grid.surface_refreshed.is_connected(_queue_layout_refresh):
			terrain_grid.surface_refreshed.disconnect(_queue_layout_refresh)
		if terrain_grid.terrain_occlusion_changed.is_connected(_on_terrain_occlusion_changed):
			terrain_grid.terrain_occlusion_changed.disconnect(_on_terrain_occlusion_changed)
	if has_node("/root/ShadowSystem"):
		var shadow_system = get_node("/root/ShadowSystem")
		if shadow_system.sun_direction_changed.is_connected(_on_sun_direction_changed):
			shadow_system.sun_direction_changed.disconnect(_on_sun_direction_changed)
	if PerformanceSettings.profile_changed.is_connected(_on_graphics_settings_changed):
		PerformanceSettings.profile_changed.disconnect(_on_graphics_settings_changed)


func set_decoration_type(type: String, data: Dictionary) -> void:
	"""Set the decoration type and load its data"""
	decoration_type = type
	decoration_data = data.duplicate(true)
	category = data.get("category", "")
	var sz = data.get("size", [1, 1])
	size = Vector2i(int(sz[0]), int(sz[1]))
	cost = data.get("cost", 0)
	daily_upkeep = data.get("daily_upkeep", 0)
	aesthetics_value = data.get("aesthetics_value", 0.0)

	if is_inside_tree():
		_generate_variation()
		_update_visuals()


func _generate_variation() -> void:
	"""Generate deterministic variation based on grid position"""
	_variation = visual_variation(decoration_type, grid_position)

static func visual_variation(type: String, pos: Vector2i) -> PropVariation.VariationResult:
	var var_params = DECORATION_VARIATION.get(type, {
		"scale": Vector2(0.95, 1.05),
		"rotation": Vector2(0.0, 0.0),
		"hue": Vector2(-0.02, 0.02)
	})

	# Use salt offset 200 to differentiate from trees (0)
	return PropVariation.generate_custom_variation(
		pos,
		var_params["scale"],
		var_params["rotation"],
		var_params["hue"],
		Vector2(-0.03, 0.03),  # Saturation
		Vector2(-0.05, 0.05)   # Value
	)


func _on_ground_changed(pos: Vector2i, _old: int, _new: int) -> void:
	if Rect2i(grid_position, size).grow(1).has_point(pos):
		_queue_layout_refresh()

func _on_vertex_elevation_changed(vertex: Vector2i, _old: int, _new: int) -> void:
	var footprint := Rect2i(grid_position, size)
	for tile in terrain_grid.tiles_around_vertex(vertex):
		if footprint.has_point(tile):
			_queue_layout_refresh()
			return
	# Ground near the prop is what its clip is measured on.
	if _occlusion_active and footprint.grow(OCCLUSION_REACH_TILES).has_point(vertex) \
			and not _occlusion_refresh_queued:
		_occlusion_refresh_queued = true
		call_deferred("refresh_terrain_occlusion")

func _queue_layout_refresh() -> void:
	if not _layout_refresh_pending:
		_layout_refresh_pending = true
		call_deferred("_refresh_layout")

func _refresh_layout() -> void:
	_layout_refresh_pending = false
	if is_inside_tree():
		# Re-anchor as well as rebuilding the artwork: a changed vertex moves the
		# decoration's ground point even when its terrain type stayed the same.
		set_position_in_grid(grid_position)
		_update_visuals()


func _input_event(_viewport: Node, event: InputEvent, _shape_idx: int) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		decoration_selected.emit(self)


func set_terrain_grid(grid: TerrainGrid) -> void:
	terrain_grid = grid


func set_position_in_grid(pos: Vector2i) -> void:
	var old_pos = grid_position
	grid_position = pos
	_anchor_tile = pos
	if terrain_grid:
		# For multi-tile decorations, position at center of footprint
		if size.x > 1 or size.y > 1:
			var center_offset = Vector2(size.x - 1, size.y - 1) * 0.5
			var center_pos = Vector2(pos.x, pos.y) + center_offset
			_anchor_tile = Vector2i(int(center_pos.x), int(center_pos.y))
		global_position = terrain_grid.grid_to_screen_center(_anchor_tile)

	if old_pos != pos and is_inside_tree():
		_generate_variation()
		_update_visuals()
	else:
		# A turn of the view comes through here too: re-aim the clip.
		refresh_terrain_occlusion()


func get_footprint() -> Array:
	"""Returns array of Vector2i positions this decoration occupies"""
	var footprint: Array = []
	for x in range(size.x):
		for y in range(size.y):
			footprint.append(grid_position + Vector2i(x, y))
	return footprint


func destroy() -> void:
	decoration_destroyed.emit(self)
	queue_free()


func get_decoration_info() -> Dictionary:
	"""Returns serializable info for saving"""
	return {
		"type": decoration_type,
		"position": {"x": grid_position.x, "y": grid_position.y},
		"category": category,
		"cost": cost,
	}


func _update_visuals() -> void:
	"""Create visual representation with shadows and variation"""
	if has_node("Visual"):
		var previous := get_node("Visual")
		remove_child(previous)
		previous.queue_free()

	var visual = Node2D.new()
	visual.name = "Visual"
	add_child(visual)
	_shadow_refs.clear()
	_shadow_config = null
	var layout := PathFurniture.layout(terrain_grid, grid_position, decoration_type)
	visual.position = layout.offset
	if PathFurniture.has_art(decoration_type):
		var furniture := PathFurniture.new()
		furniture.name = "PathFurniture"
		furniture.kind = decoration_type
		furniture.facing = layout.facing
		visual.add_child(furniture)
		refresh_terrain_occlusion()
		return

	var base_color = DECORATION_COLORS.get(decoration_type, Color.WHITE)
	# A decoration defined by data (the shape a mod ships) can name the colour
	# its procedural drawing is painted in.
	var data_color: Variant = decoration_data.get("color", null)
	if data_color is String and not str(data_color).is_empty():
		base_color = Color.html(str(data_color))
	elif data_color is Color:
		base_color = data_color
	var color = base_color
	if _variation:
		color = _variation.apply_color_shift(base_color)

	# Configure shadow
	var vis_data = DECORATION_VISUALS.get(decoration_type, {"visual_height": 16.0, "base_width": 20.0})
	var visual_height = vis_data["visual_height"]
	var base_width = vis_data["base_width"]
	# The Visual parent applies variation to both sprite and shadow. Anchor at
	# the sprite foot; a positive offset detached the contact shadow from it.
	_shadow_config = ShadowRenderer.ShadowConfig.new(visual_height, base_width)
	_shadow_config.base_offset = Vector2.ZERO

	# Small decorations skip drop shadow
	if visual_height <= 16.0:
		_shadow_config.cast_drop_shadow = false

	var shadow_system: Node = null
	if has_node("/root/ShadowSystem"):
		shadow_system = get_node("/root/ShadowSystem")

	_shadow_refs = ShadowRenderer.add_shadows_to_entity(visual, _shadow_config, shadow_system)
	_shadow_detail_built = PerformanceSettings.shadow_detail

	# Use sprite if available, otherwise procedural fallback
	if decoration_type in SPRITE_PATHS and ResourceLoader.exists(SPRITE_PATHS[decoration_type]):
		var sprite = Sprite2D.new()
		sprite.name = "DecorationSprite"
		sprite.texture = load(SPRITE_PATHS[decoration_type])
		sprite.centered = true
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		if _variation:
			sprite.modulate = _variation.apply_color_shift(Color.WHITE)
		var offset_y = SPRITE_BASE_OFFSETS.get(decoration_type, 16.0)
		sprite.position.y = -offset_y
		visual.add_child(sprite)
	else:
		_draw_procedural(visual, color)

	# Apply scale and rotation variation
	if decoration_type == "fountain":
		var atmosphere := DecorationAtmosphere.new()
		atmosphere.name = "Atmosphere"
		atmosphere.terrain_grid = terrain_grid
		# Keep the falling beads aligned with the newly grounded sprite.
		atmosphere.position.y = -5.0
		visual.add_child(atmosphere)

	if _variation:
		visual.scale = Vector2(_variation.scale, _variation.scale)
		visual.rotation = _variation.rotation
	refresh_terrain_occlusion()


## Clip the prop wherever a nearer hill covers it, as trees are clipped, while
## the course has relief and the graphics setting allows it (see
## TerrainGrid.terrain_occlusion_enabled()). The art is a billboard standing on
## its tile's centre, measured from the art's lowest pixel - a bench set out to
## the edge of a path is measured from its front feet - so the ground under its
## own base never cuts into it (TerrainOcclusion.contact_reach()); the shadows
## are paint on the ground, every point of them carrying the grid point of the
## ground drawn under it (`shadow_grounds()`). Runs again whenever the prop is
## laid out, moves or has its shadows rebuilt, the view turns, or the ground
## near it is sculpted. Only a prop drawn on the course's own canvas is clipped.
func refresh_terrain_occlusion() -> void:
	_occlusion_refresh_queued = false
	var visual := get_node_or_null("Visual") as Node2D
	var grid := terrain_grid if is_instance_valid(terrain_grid) else null
	_occlusion_active = visual != null and is_inside_tree() and grid != null and grid.is_inside_tree() \
			and grid._course_surface != null and grid.terrain_occlusion_enabled() \
			and get_canvas() == grid.get_canvas()
	if not _occlusion_active:
		if visual != null:
			visual.material = null
		for shadow in _shadow_polygons():
			shadow.material = null
			shadow.texture = null
			shadow.uv = PackedVector2Array()
		return
	var anchor := Vector2(_anchor_tile) + Vector2(0.5, 0.5)
	if _art_material == null:
		_art_material = ShaderMaterial.new()
		_art_material.shader = TERRAIN_SPRITE_OCCLUSION
		_art_material.set_shader_parameter("occlusion_epsilon", TerrainOcclusion.PROP_EPSILON)
	var below := to_global(visual.position).y + art_reach() - grid.grid_point_to_screen(anchor).y
	var lift := TerrainOcclusion.contact_reach(grid, anchor, below) if below > 0.0 else 0.0
	grid._course_surface.configure_sprite_occlusion(_art_material, anchor, Vector2(0.0, lift))
	visual.material = _art_material
	_clip_art_below(visual)
	var shadows := _shadow_polygons()
	if shadows.is_empty():
		return
	if _shadow_material == null:
		_shadow_material = ShaderMaterial.new()
		_shadow_material.shader = TERRAIN_DECAL_OCCLUSION
		_shadow_material.set_shader_parameter("occlusion_epsilon", TerrainOcclusion.SHADOW_EPSILON)
	grid._course_surface.configure_terrain_occlusion(_shadow_material)
	for shadow in shadows:
		# A Polygon2D only hands its UVs to the renderer while it has a texture.
		shadow.texture = GroundDecal.uv_carrier()
		shadow.uv = shadow_grounds(shadow, anchor)
		shadow.material = _shadow_material

## The ground under each point of a shadow cast by a prop standing on the grid
## point `anchor`: the grid point drawn there, found from the anchor
## (GroundDecal.ground_under()). Where the ground turns too far from the view
## for that to be found, the whole shadow stands on the anchor instead, as the
## art does (GroundDecal.stand_on()), so it is never cut by the ground it lies on.
func shadow_grounds(shadow: Polygon2D, anchor: Vector2) -> PackedVector2Array:
	var world_points := PackedVector2Array()
	var grounds := PackedVector2Array()
	var found := true
	for point in shadow.polygon:
		var world := shadow.to_global(point)
		var ground := GroundDecal.ground_under(terrain_grid, world, anchor)
		found = found and terrain_grid.grid_point_to_screen(ground).distance_to(world) < SHADOW_GROUND_MISS
		world_points.append(world)
		grounds.append(ground)
	if not found:
		var depth_y := GroundDecal.standing_depth_y(terrain_grid, anchor, world_points)
		for i in world_points.size():
			grounds[i] = GroundDecal.standing_ground(terrain_grid, world_points[i], depth_y)
	return grounds

## How far below its foot (the origin of its Visual) the prop's art reaches
## down the screen, in pixels. A sprite is cut so that its lowest visible pixel
## is the foot itself (SPRITE_BASE_OFFSETS); path furniture and the drawn
## fallback shapes reach a little further down, toward the viewer.
func art_reach() -> float:
	var visual := get_node_or_null("Visual") as Node2D
	if visual == null:
		return 0.0
	var reach := 0.0
	for child in visual.get_children():
		if _is_shadow(child):
			continue
		if child is PathFurniture:
			var furniture := child as PathFurniture
			reach = maxf(reach, PathFurniture.ground_reach(furniture.kind, furniture.facing) * absf(visual.scale.y))
		elif child is Polygon2D:
			var part := child as Polygon2D
			for point in part.polygon:
				reach = maxf(reach, visual.transform.basis_xform(part.transform * point).y)
	return reach

## Whether the terrain hides the prop's pixel at a world point: the test its art's
## occlusion shader runs.
func terrain_hides_point(world: Vector2) -> bool:
	if not _occlusion_active or _art_material == null:
		return false
	return TerrainOcclusion.hides_with_material(terrain_grid, _art_material, world)

## Every part of the art - the sprite or the furniture, the drawn shapes, a
## fountain's spray - wears the art's material; the shadows wear their own.
func _clip_art_below(node: Node) -> void:
	for child in node.get_children():
		if child is CanvasItem and not _is_shadow(child):
			(child as CanvasItem).use_parent_material = true
			_clip_art_below(child)

func _shadow_polygons() -> Array[Polygon2D]:
	var shadows: Array[Polygon2D] = []
	for shadow in _shadow_refs.values():
		if shadow is Polygon2D and is_instance_valid(shadow):
			shadows.append(shadow)
	return shadows

func _is_shadow(node: Node) -> bool:
	return node is Polygon2D and _shadow_refs.values().has(node)

func _on_terrain_occlusion_changed(_enabled: bool) -> void:
	refresh_terrain_occlusion()


func _draw_procedural(visual: Node2D, color: Color) -> void:
	"""Draw a simple procedural representation based on decoration type"""
	match category:
		"water":
			_draw_water_feature(visual, color)
		"structures":
			_draw_structure(visual, color)
		"furniture":
			_draw_furniture(visual, color)
		"sculptures":
			_draw_sculpture(visual, color)
		_:
			_draw_generic(visual, color)


func _draw_water_feature(visual: Node2D, color: Color) -> void:
	"""Draw the fountain: a basin, a water surface, a pillar and its spray"""
	# Basin
	var basin = Polygon2D.new()
	basin.color = Color(0.55, 0.55, 0.60)
	basin.polygon = PackedVector2Array([
		Vector2(-16, 4), Vector2(-14, -2), Vector2(14, -2), Vector2(16, 4),
		Vector2(14, 8), Vector2(-14, 8)
	])
	visual.add_child(basin)
	# Water surface
	var water = Polygon2D.new()
	water.color = Color(color.r, color.g, color.b, 0.7)
	water.polygon = PackedVector2Array([
		Vector2(-12, 2), Vector2(-10, -1), Vector2(10, -1), Vector2(12, 2),
		Vector2(10, 5), Vector2(-10, 5)
	])
	visual.add_child(water)
	# Center pillar
	var pillar = Polygon2D.new()
	pillar.color = Color(0.60, 0.60, 0.65)
	pillar.polygon = PackedVector2Array([
		Vector2(-2, 2), Vector2(2, 2), Vector2(2, -14), Vector2(-2, -14)
	])
	visual.add_child(pillar)
	# Water spray highlight
	var spray = Polygon2D.new()
	spray.color = Color(0.7, 0.85, 1.0, 0.6)
	spray.polygon = _make_circle_polygon(4.0, 5, Vector2(0, -16))
	visual.add_child(spray)


func _draw_structure(visual: Node2D, color: Color) -> void:
	"""Draw the ball washer: a small post with its mechanism"""
	var post = Polygon2D.new()
	post.color = Color(0.40, 0.40, 0.45)
	post.polygon = PackedVector2Array([
		Vector2(-1, 4), Vector2(1, 4), Vector2(1, -6), Vector2(-1, -6)
	])
	visual.add_child(post)
	var washer = Polygon2D.new()
	washer.color = color
	washer.polygon = PackedVector2Array([
		Vector2(-4, -6), Vector2(4, -6), Vector2(4, -12), Vector2(-4, -12)
	])
	visual.add_child(washer)


func _draw_furniture(visual: Node2D, color: Color) -> void:
	"""Draw the park bench: a seat, a back rest and its legs"""
	# Bench seat
	var seat = Polygon2D.new()
	seat.color = color
	seat.polygon = PackedVector2Array([
		Vector2(-12, 0), Vector2(12, 0), Vector2(12, 3), Vector2(-12, 3)
	])
	visual.add_child(seat)
	# Back rest
	var back = Polygon2D.new()
	back.color = Color(color.r * 0.85, color.g * 0.85, color.b * 0.85)
	back.polygon = PackedVector2Array([
		Vector2(-12, 0), Vector2(12, 0), Vector2(12, -6), Vector2(-12, -6)
	])
	visual.add_child(back)
	# Legs
	for x_off in [-10, 10]:
		var leg = Polygon2D.new()
		leg.color = Color(0.30, 0.30, 0.30)
		leg.polygon = PackedVector2Array([
			Vector2(x_off - 1, 3), Vector2(x_off + 1, 3),
			Vector2(x_off + 1, 7), Vector2(x_off - 1, 7)
		])
		visual.add_child(leg)


func _draw_sculpture(visual: Node2D, color: Color) -> void:
	"""Draw sculpture decorations (golfer statue, sundial)"""
	if decoration_type == "golfer_statue":
		# Pedestal
		var pedestal = Polygon2D.new()
		pedestal.color = Color(0.50, 0.50, 0.50)
		pedestal.polygon = PackedVector2Array([
			Vector2(-8, 4), Vector2(8, 4), Vector2(6, -2), Vector2(-6, -2)
		])
		visual.add_child(pedestal)
		# Figure (simplified golfer silhouette)
		var figure = Polygon2D.new()
		figure.color = color
		figure.polygon = PackedVector2Array([
			Vector2(-3, -2), Vector2(3, -2), Vector2(4, -16), Vector2(6, -20),
			Vector2(4, -22), Vector2(2, -18), Vector2(-2, -18), Vector2(-2, -24),
			Vector2(2, -24), Vector2(0, -26), Vector2(-4, -22), Vector2(-4, -16)
		])
		visual.add_child(figure)
	else:
		# Sundial - flat disc on pedestal
		var pedestal = Polygon2D.new()
		pedestal.color = Color(0.55, 0.55, 0.55)
		pedestal.polygon = PackedVector2Array([
			Vector2(-4, 4), Vector2(4, 4), Vector2(3, -4), Vector2(-3, -4)
		])
		visual.add_child(pedestal)
		var disc = Polygon2D.new()
		disc.color = color
		disc.polygon = PackedVector2Array([
			Vector2(-8, -4), Vector2(8, -4), Vector2(10, -7), Vector2(8, -10),
			Vector2(-8, -10), Vector2(-10, -7)
		])
		visual.add_child(disc)
		# Gnomon (shadow casting pin)
		var gnomon = Polygon2D.new()
		gnomon.color = Color(0.30, 0.30, 0.30)
		gnomon.polygon = PackedVector2Array([
			Vector2(-1, -7), Vector2(1, -7), Vector2(0, -14)
		])
		visual.add_child(gnomon)


func _draw_generic(visual: Node2D, color: Color) -> void:
	"""Fallback generic decoration shape"""
	var shape = Polygon2D.new()
	shape.color = color
	shape.polygon = _make_circle_polygon(10.0, 6, Vector2(0, -4))
	visual.add_child(shape)


func _make_circle_polygon(radius: float, segments: int, offset: Vector2 = Vector2.ZERO) -> PackedVector2Array:
	"""Generate a circle-approximating polygon"""
	var points = PackedVector2Array()
	for i in range(segments):
		var angle = TAU * i / segments
		points.append(Vector2(cos(angle) * radius, sin(angle) * radius) + offset)
	return points


func _on_sun_direction_changed(_direction: Vector2) -> void:
	"""Update shadows when sun direction changes"""
	_rebuild_shadows()


## The graphics quality owns how many shadow polygons a prop carries: redraw
## this one from the shapes the new setting allows, keeping the sprite as it is.
func _on_graphics_settings_changed(_terrain_fast: bool) -> void:
	if PerformanceSettings.shadow_detail == _shadow_detail_built:
		return
	_rebuild_shadows()


func _rebuild_shadows() -> void:
	if _shadow_config == null or not has_node("Visual"):
		return
	var visual = get_node("Visual")
	var shadow_system: Node = null
	if has_node("/root/ShadowSystem"):
		shadow_system = get_node("/root/ShadowSystem")
	# Remove old shadows
	for key in _shadow_refs:
		if _shadow_refs[key] and is_instance_valid(_shadow_refs[key]):
			_shadow_refs[key].queue_free()
	_shadow_refs.clear()
	_shadow_refs = ShadowRenderer.add_shadows_to_entity(visual, _shadow_config, shadow_system)
	_shadow_detail_built = PerformanceSettings.shadow_detail
	refresh_terrain_occlusion()
