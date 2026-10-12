extends MainSceneTest
## Generated courses — Quick Start and the prebuilt packages — deliver every
## hole and leave no tee box or cup waiting (a generated one would block the
## player's next tee box). They arrive with the path network that walks the
## course, laid beside every tee and green over ground the Path tool accepts,
## and every tee tile carries an aiming arrow at its hole's cup that stays
## inside the grass of its own tile, on sculpted ground too.

const PACKAGES := {"starter": 3, "executive": 9, "standard9": 9, "championship18": 18}
const SIDES: Array[Vector2i] = [Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1)]

var grid: TerrainGrid


func before_all() -> void:
	await super()
	await quick_start("Generated courses")
	grid = main.terrain_grid


# ---------------------------------------------------------------------------
# Quick Start
# ---------------------------------------------------------------------------

func test_quick_start_delivers_nine_holes_with_nothing_waiting() -> void:
	var course: GameManager.CourseData = GameManager.current_course
	assert_eq(course.holes.size(), 9, "Quick Start builds nine holes")
	assert_true(grid.get_cup_tiles().is_empty(), "Quick Start leaves no waiting cup")
	assert_true(HoleLayout.unused_tee_boxes(grid, course).is_empty(),
		"Quick Start leaves no unused tee box, so the player can place one")
	assert_true(HoleLayout.can_place_tee_box(grid, course), "The player can add a tee box")
	assert_true(HoleLayout.green_places_cup(grid, course), "The player's next green carries a cup")
	_assert_holes_walked("Quick Start")


func test_every_tee_aims_at_its_cup_inside_its_own_tile() -> void:
	var overlay: TeeAimOverlay = grid.get_node_or_null("TeeAimOverlay")
	assert_not_null(overlay, "TerrainGrid builds a TeeAimOverlay")
	if overlay == null:
		return
	overlay.rebuild()
	var tees: Array = grid.get_tee_box_tiles()
	assert_false(tees.is_empty(), "The generated course has tee boxes")
	assert_eq(overlay.aimed_tees().size(), tees.size(), "Every tee box on an open hole carries an arrow")

	var curved := 0
	for tee in overlay.aimed_tees():
		var hole := _hole_of_tee(tee)
		assert_not_null(hole, "The arrow on tee %s belongs to a hole" % tee)
		if hole == null:
			continue
		var route: Array = overlay.route_for(tee)
		assert_eq(route[0], tee, "The arrow on %s starts on its own tile" % tee)
		assert_eq(route[-1], hole.hole_position, "The arrow on %s aims at hole %d's cup" % [tee, hole.hole_number])
		if route.size() == 3:
			curved += 1
		_assert_marker_inside_tile(overlay, tee)
	assert_gt(curved, 0, "At least one dogleg gets a curved arrow")
	assert_lt(curved, tees.size(), "Straight holes keep the straight arrow")

	# The same tile with its corners pulled apart: the marker follows the ground.
	var tee: Vector2i = tees[0]
	grid.set_vertex_elevation(tee, grid.BASE_ELEVATION + 4)
	grid.set_vertex_elevation(Vector2i(tee.x + 1, tee.y), grid.BASE_ELEVATION - 3)
	overlay.rebuild()
	_assert_marker_inside_tile(overlay, tee)


# ---------------------------------------------------------------------------
# Prebuilt packages
# ---------------------------------------------------------------------------

func test_every_prebuilt_package_delivers_its_holes_with_nothing_waiting() -> void:
	for package_id in PACKAGES:
		# A package is only ever built on a fresh course: reset the grid so the
		# previous package's tee boxes do not leak into this one.
		grid.begin_batch()
		grid.deserialize({})
		grid.clear_cup_tiles()
		grid.end_batch_quiet()
		grid.begin_batch()
		PrebuiltCourseGenerator.build(package_id, grid, main.hole_tool)
		grid.end_batch_quiet()
		grid.refresh_all_overlays()
		await process_frames(4)
		assert_eq(GameManager.current_course.holes.size(), PACKAGES[package_id],
			"%s builds all its holes" % package_id)
		assert_true(grid.get_cup_tiles().is_empty(), "%s leaves no waiting cup" % package_id)
		assert_true(HoleLayout.unused_tee_boxes(grid, GameManager.current_course).is_empty(),
			"%s leaves no unused tee box" % package_id)


## A package reaches the player through the same new-game step as Quick Start,
## so it arrives with its paths too.
func test_a_prebuilt_package_started_through_the_game_arrives_with_its_paths() -> void:
	main._prebuilt_pending = "starter"
	main._prebuilt_money = GameManager.money
	main._on_new_game_started()
	await process_frames(12)
	assert_eq(GameManager.current_course.holes.size(), PACKAGES["starter"], "The Starter Pack builds its holes")
	_assert_holes_walked("Starter Pack")


# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------

## The paths a generated course arrives with. A trail is only laid on ground the
## Path tool accepts — never on the playing line, a green, a tee, sand or water —
## so what a course arrives with is a walk beside every tee and green, in as many
## networks as its corridors seal off.
func _assert_holes_walked(course_name: String) -> void:
	var reach: int = CoursePathGenerator.HUB_RINGS + 2
	var paths := _path_tiles()
	assert_gte(paths.size(), 10, "%s arrives with paths" % course_name)
	var refused := 0
	for tile in paths:
		if not TerrainTypes.can_host_walking_path(grid.get_tile(tile)):
			refused += 1
	assert_eq(refused, 0, "%s lays no trail on ground the Path tool refuses" % course_name)

	for hole in GameManager.current_course.holes:
		var label := "%s hole %d" % [course_name, hole.hole_number]
		assert_true(_within(paths, hole.tee_position, reach), "%s: the tee has its walk" % label)
		assert_true(_within(paths, hole.hole_position, reach), "%s: the green has its walk" % label)
		assert_eq(grid.get_tile(hole.tee_position), TerrainTypes.Type.TEE_BOX, "%s: the tee is a tee box" % label)
		assert_eq(grid.get_tile(hole.hole_position), TerrainTypes.Type.GREEN, "%s: the cup is on its green" % label)

	var clubhouse := CourseClubhouse.find(main.entity_layer)
	assert_not_null(clubhouse, "%s has a clubhouse to walk out of" % course_name)
	if clubhouse:
		var edges: Dictionary = {}
		for footprint in clubhouse.get_footprint():
			for side in SIDES:
				edges[footprint + side] = true
		gut.p("%s: %d trail tiles, %d paved by the clubhouse" % [course_name, paths.size(),
			WalkingPathOverlay.upgraded_component_tiles(paths, edges).size()])


## Every tile of the course that carries a trail.
func _path_tiles() -> Dictionary:
	var tiles: Dictionary = {}
	for y in range(grid.grid_height):
		for x in range(grid.grid_width):
			if grid.has_walking_path(Vector2i(x, y)):
				tiles[Vector2i(x, y)] = true
	return tiles


## Is a trail within `reach` tiles of `centre`?
func _within(paths: Dictionary, centre: Vector2i, reach: int) -> bool:
	for x in range(-reach, reach + 1):
		for y in range(-reach, reach + 1):
			if paths.has(centre + Vector2i(x, y)):
				return true
	return false


func _hole_of_tee(tee: Vector2i) -> GameManager.HoleData:
	for hole in GameManager.current_course.holes:
		if hole.tee_position == tee:
			return hole
	return null


## Shaft, head and both red markers lie inside the tile's projected outline; on
## ground too steep for that, the marker keeps a readable size and only promises
## to stay over its tile.
func _assert_marker_inside_tile(overlay: TeeAimOverlay, tee: Vector2i) -> void:
	var layout: Dictionary = overlay.marker_layout(tee)
	assert_false(layout.is_empty(), "Tee %s has marker geometry" % tee)
	if layout.is_empty():
		return
	var polygon := PackedVector2Array()
	for corner in grid.tile_polygon(tee):
		polygon.append(overlay.to_local(corner))
	var points := PackedVector2Array()
	points.append_array(layout.shaft)
	points.append_array(layout.head)
	points.append_array(layout.balls)
	var box := Rect2(polygon[0], Vector2.ZERO)
	for corner in polygon:
		box = box.expand(corner)
	var outside := 0
	for point in points:
		var inside := box.has_point(point) if layout.floored else Geometry2D.is_point_in_polygon(point, polygon)
		if not inside:
			outside += 1
	assert_eq(outside, 0, "Every point of tee %s's marker stays on its tile" % tee)
