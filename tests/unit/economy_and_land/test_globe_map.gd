extends GameTest
## The world map's globe: the baked land mask the planet shader samples, the
## two-layer split (shader planet underneath, markers on top), and the view
## animations. The shader itself cannot be compiled without a GPU, so
## `test_the_planet_shader_stays_in_step_with_the_script` checks the contract
## between the shader's uniforms and the values GlobeMap pushes at them.

const SHADER_PATH := "res://shaders/globe_planet.gdshader"

## Uniforms the script sets by name.
const SCRIPT_UNIFORMS := ["land_mask", "mask_size", "view_size",
	"center_lon_deg", "center_lat_deg", "radius_scale"]

func _make_globe(style: int = GlobeMap.LandStyle.PLANET) -> GlobeMap:
	var globe := GlobeMap.new()
	globe.set_land_style(style)
	globe.size = Vector2(480, 360)
	add_child_autofree(globe)
	return globe

## ── The baked land mask ──────────────────────────────────────────────────

func test_the_baked_mask_agrees_with_the_land_polygons() -> void:
	# The mask is the shader's only idea of where the land is, so it has to
	# agree with the polygon test the rest of the game uses. Disagreements are
	# only allowed on coastline texels, where the mask stores coverage.
	var mask := GlobeMap.build_land_mask()
	seed(20261004)
	var mismatches := 0
	var samples := 600
	for i in range(samples):
		var lon := randf_range(-180.0, 180.0)
		var lat := randf_range(-88.0, 88.0)
		if (GlobeMap.mask_coverage(mask, lon, lat) > 0.5) != GlobeMap.is_land(lon, lat):
			mismatches += 1
	assert_lt(mismatches, int(samples * 0.03),
		"the mask matches the land polygons away from the coastlines (%d/%d differ)" % [mismatches, samples])

func test_the_mask_puts_known_places_on_the_right_side_of_the_coast() -> void:
	var mask := GlobeMap.build_land_mask()
	assert_lt(GlobeMap.mask_coverage(mask, -30.0, 40.0), 0.5, "mid-Atlantic stays water")
	assert_gt(GlobeMap.mask_coverage(mask, 15.0, 22.0), 0.5, "the Sahara is land")
	assert_gt(GlobeMap.mask_coverage(mask, -60.0, -5.0), 0.5, "the Amazon is land")
	assert_lt(GlobeMap.mask_coverage(mask, -140.0, 0.0), 0.5, "the mid-Pacific stays water")
	assert_gt(GlobeMap.mask_coverage(mask, 100.0, -75.0), 0.5, "Antarctica is drawn as a polar cap")
	assert_gt(GlobeMap.mask_coverage(mask, 20.0, 0.0), 0.5, "the equator runs through land in central Africa")
	assert_lt(GlobeMap.mask_coverage(mask, 0.0, 0.0), 0.5, "and through water in the Gulf of Guinea")
	assert_gt(GlobeMap.mask_coverage(mask, -19.0, 65.0), 0.5, "Iceland is kept as its own island")
	assert_lt(GlobeMap.mask_coverage(mask, -12.0, 65.0), 0.5, "the water east of Iceland is not filled in")
	assert_lt(GlobeMap.mask_coverage(mask, 50.0, 42.0), 0.5, "the Caspian Sea remains a hole in Eurasia")
	assert_lt(GlobeMap.mask_coverage(mask, 122.0, 10.0), 0.5, "the Philippine Sea is not swallowed by a blocky island outline")
	assert_lt(GlobeMap.mask_coverage(mask, 113.0, -5.0), 0.5, "the Java Sea remains water between the islands")
	assert_gt(GlobeMap.mask_coverage(mask, 121.0, 14.0), 0.5, "Luzon remains land beside the Philippine Sea")
	assert_gt(GlobeMap.mask_coverage(mask, -179.0, -89.0), 0.5, "Antarctica remains land across the western date line")
	assert_gt(GlobeMap.mask_coverage(mask, 179.0, -89.0), 0.5, "the eastern date line closes the polar coastline")

func test_the_land_data_has_detailed_coastlines_and_separate_islands() -> void:
	var polygons := GlobeMap._get_polygons()
	assert_gt(polygons.size(), 1400, "the bundled Natural Earth data keeps separate land shapes")
	var vertices := 0
	var holes := 0
	for polygon: Array in polygons:
		if polygon.size() > 1:
			holes += polygon.size() - 1
		for ring: PackedVector2Array in polygon:
			vertices += ring.size()
	assert_gt(vertices, 20000, "the atlas has detailed coastline vertices rather than a handful of hand-drawn points")
	assert_gt(holes, 0, "interior water rings are retained")
	assert_true(GlobeMap.is_land(-19.0, 65.0), "Iceland's outline includes its interior")
	assert_false(GlobeMap.is_land(-12.0, 65.0), "nearby North Atlantic water stays water")
	assert_false(GlobeMap.is_land(50.0, 42.0), "the Caspian Sea hole is not reported as land")
	assert_true(GlobeMap.is_land(121.0, 14.0), "the Luzon coastline is represented")
	assert_false(GlobeMap.is_land(122.0, 10.0), "water in the Philippine archipelago is not filled as land")
	assert_true(GlobeMap.is_land(115.2, -8.4), "Bali is represented as a separate island")
	assert_false(GlobeMap.is_land(113.0, -5.0), "the Java Sea between islands stays water")

func test_the_mask_bake_is_shared_by_every_globe() -> void:
	GlobeMap.clear_mask_cache()
	var first := GlobeMap.get_land_mask_texture()
	var second := GlobeMap.get_land_mask_texture()
	assert_same(first, second, "the mask texture is cached, not rebuilt per globe")
	assert_eq(GlobeMap.mask_bake_count(), 1, "the mask rasterises exactly once per run")

func test_mask_uv_wraps_longitude_and_stays_inside_the_poles() -> void:
	assert_almost_eq(GlobeMap.mask_uv(0.0, 0.0).x, 0.5, 0.0001, "Greenwich is the middle of the mask")
	assert_almost_eq(GlobeMap.mask_uv(-180.0, 0.0).x, 0.0, 0.0001, "the antimeridian is the left edge")
	assert_almost_eq(GlobeMap.mask_uv(180.0, 0.0).x, 0.0, 0.0001, "and the right edge wraps onto it")
	assert_almost_eq(GlobeMap.mask_uv(190.0, 0.0).x, GlobeMap.mask_uv(-170.0, 0.0).x, 0.0001,
		"longitudes past the date line keep wrapping")
	assert_between(GlobeMap.mask_uv(0.0, 90.0).y, 0.0, 0.01, "the north pole is kept inside the top row")
	assert_between(GlobeMap.mask_uv(0.0, -90.0).y, 0.99, 1.0, "the south pole is kept inside the bottom row")

## ── The two layers ───────────────────────────────────────────────────────

func test_the_planet_layer_runs_the_shader_with_the_baked_mask() -> void:
	var globe := _make_globe()
	await process_frames(1)
	assert_true(is_instance_valid(globe._planet), "the planet surface exists")
	assert_true(globe._planet_material != null, "the planet has its own material")
	assert_eq(globe._planet_material.shader, load(SHADER_PATH), "the planet runs the globe shader")
	assert_same(globe._planet_material.get_shader_parameter("land_mask"), GlobeMap.get_land_mask_texture(),
		"the planet samples the shared land mask")

func test_markers_draw_over_the_planet_on_their_own_layer() -> void:
	var globe := _make_globe()
	await process_frames(1)
	assert_true(is_instance_valid(globe._marker_layer), "the marker layer exists")
	assert_gt(globe._marker_layer.get_index(), globe._planet.get_index(),
		"the marker layer is above the planet, so pins stay readable")
	assert_eq(globe._marker_layer.mouse_filter, Control.MOUSE_FILTER_IGNORE,
		"the layers never steal the globe's drags or clicks")

func test_markers_are_placed_for_the_near_side_only() -> void:
	var globe := _make_globe()
	globe.set_view_state({"center_lon": 0.0, "center_lat": 0.0, "radius_scale": 1.0})
	globe.set_locations([
		{"id": "greenwich", "name": "Greenwich", "lon": 0.0, "lat": 0.0},
		{"id": "antipode", "name": "Antipode", "lon": 180.0, "lat": 0.0},
	])
	await process_frames(2)
	assert_true(globe.has_marker_on_screen("greenwich"), "the destination facing the player has a marker")
	assert_false(globe.has_marker_on_screen("antipode"), "the far side of the globe has none")
	assert_almost_eq(globe.get_marker_position("greenwich").x, globe.size.x * 0.5, 1.0,
		"the marker sits on the globe's vertical axis")

func test_hovering_or_selecting_never_re_shades_the_planet() -> void:
	var globe := _make_globe()
	await process_frames(1)
	globe.set_locations([
		{"id": "greenwich", "name": "Greenwich", "lon": 0.0, "lat": 0.0},
		{"id": "scotland", "name": "Scotland", "lon": -4.2, "lat": 56.5},
	])
	await process_frames(1)
	var syncs := globe.view_sync_count()
	globe.set_selected("scotland")
	globe.set_locations(globe._locations)
	await process_frames(1)
	assert_eq(globe.view_sync_count(), syncs,
		"selection and list refreshes only repaint the marker layer")
	globe.look_at_location("scotland")
	for i in range(12):
		globe._process(0.1)
	assert_gt(globe.view_sync_count(), syncs, "moving the globe does re-shade the planet")

func test_the_dots_style_keeps_a_shader_free_fallback_available() -> void:
	var globe := _make_globe(GlobeMap.LandStyle.DOTS)
	assert_eq(globe.get_land_style(), GlobeMap.LandStyle.DOTS)
	assert_false(is_instance_valid(globe._planet), "the dots style builds no shader planet")
	assert_true(is_instance_valid(globe._marker_layer), "markers still get their own layer")
	await process_frames(2)
	assert_gt(globe._land_points.size(), 1000, "the detailed land mask supplies the shader-free dots")

func test_pixel_planet_uses_a_finer_cell_grid_for_its_coastlines() -> void:
	var globe := autofree(GlobeMap.new()) as GlobeMap
	globe.size = Vector2(600.0, 600.0)
	assert_eq(globe._pixel_block_size(), 3.5,
		"the world map's pixel grid is finer than the former 4.5px limit")

## ── View animation ───────────────────────────────────────────────────────

func test_centring_takes_the_short_way_round_the_globe() -> void:
	var globe := _make_globe()
	globe.set_view_state({"center_lon": 170.0, "center_lat": 0.0, "radius_scale": 1.0})
	globe.set_locations([{"id": "west", "name": "West", "lon": -170.0, "lat": 10.0}])
	globe.look_at_location("west")
	assert_almost_eq(globe._anim_to_lon, 190.0, 0.001,
		"the target wraps east past the date line instead of unwinding the long way")
	globe._process(0.1)
	assert_gt(globe._center_lon, 170.0, "the globe heads east over the date line, not back across Asia")
	assert_lt(globe._center_lon, 190.0, "still on its way there")
	for i in range(12):
		globe._process(0.1)
	assert_almost_eq(globe._center_lon, -170.0, 0.01,
		"the move arrives and the centre is wrapped back into -180..180")
	assert_almost_eq(globe._center_lat, 10.0, 0.01, "and takes the latitude with it")
	assert_false(globe.is_processing(), "the globe stops animating once it has arrived")

func test_centring_animation_is_smooth_and_monotonic() -> void:
	var globe := _make_globe()
	globe.set_view_state({"center_lon": 0.0, "center_lat": 0.0, "radius_scale": 1.0})
	globe.set_locations([{"id": "east", "name": "East", "lon": 90.0, "lat": 0.0}])
	globe.look_at_location("east")
	var previous := globe._center_lon
	var steps := 0
	for i in range(40):
		globe._process(0.05)
		assert_gt(globe._center_lon, previous, "the globe keeps closing on its target")
		steps += 1
		if not globe._animating:
			break
	assert_almost_eq(globe._center_lon, 90.0, 0.001, "it lands exactly on the destination")
	assert_gt(steps, 2, "the move is interpolated over several frames, not snapped")

func test_a_frozen_simulation_does_not_freeze_the_globe() -> void:
	# The Club tab opens the World Map over a course it has paused, and a paused
	# simulation runs on Engine.time_scale 0: every frame it hands out is worth
	# no time at all. The atlas is an interface rather than part of the
	# simulation, so it measures its own time and keeps turning.
	var globe := _make_globe()
	globe.set_view_state({"center_lon": 0.0, "center_lat": 0.0, "radius_scale": 1.0})
	globe.set_locations([{"id": "east", "name": "East", "lon": 90.0, "lat": 0.0}])
	globe.look_at_location("east")
	Engine.time_scale = 0.0
	# The frame already in flight still carries the last of the running clock,
	# so let the frozen clock settle before watching the globe.
	await process_frames(2)
	var progress: float = globe._anim_time
	var centre: float = globe._center_lon
	await process_frames(6)
	assert_gt(globe._anim_time, progress, "the fly-to keeps its own time while the course is frozen")
	assert_gt(globe._center_lon, centre, "and carries the globe towards the destination")

	var radius: float = globe.get_view_state()["radius_scale"]
	globe.zoom_in()
	await process_frames(6)
	assert_gt(globe.get_view_state()["radius_scale"], radius,
		"zooming eases towards its target over a frozen course too")


func test_taking_hold_of_the_globe_stops_a_fly_to_in_flight() -> void:
	# A hand on the globe overrules whatever it was doing: a fly-to left in
	# flight writes its own centre over every frame of the drag, and the globe
	# seems to refuse to follow the pointer.
	var globe := _make_globe()
	globe.set_view_state({"center_lon": 0.0, "center_lat": 0.0, "radius_scale": 1.0})
	globe.set_locations([{"id": "east", "name": "East", "lon": 90.0, "lat": 0.0}])
	globe.look_at_location("east")
	assert_true(globe._animating, "the globe is flying towards the destination")

	var press := InputEventMouseButton.new()
	press.button_index = MOUSE_BUTTON_LEFT
	press.pressed = true
	press.position = Vector2(200.0, 180.0)
	globe._gui_input(press)
	assert_false(globe._animating, "taking hold of the globe cancels the fly-to")

	var before := globe._center_lon
	var motion := InputEventMouseMotion.new()
	motion.position = press.position + Vector2(60.0, 0.0)
	globe._gui_input(motion)
	var dragged := globe._center_lon
	assert_true(absf(dragged - before) > 10.0, "the drag turns the globe")
	await process_frames(3)
	assert_almost_eq(globe._center_lon, dragged, 0.001,
		"and the globe stays where the drag left it")


func test_zoom_eases_to_its_target_and_stops_processing() -> void:
	var globe := _make_globe()
	var start: float = globe.get_view_state()["radius_scale"]
	globe.zoom_in()
	assert_almost_eq(globe.get_view_state()["radius_scale"], start, 0.0001,
		"the zoom sets a target instead of jumping there")
	assert_gt(globe._zoom_target, start, "the target is the zoomed-in radius")
	for i in range(40):
		globe._process(0.05)
	assert_almost_eq(globe._radius_scale, start * GlobeMap.ZOOM_STEP, 0.0001, "the zoom reaches its target")
	assert_almost_eq(globe._zoom_target, globe._radius_scale, 0.0001, "and stops there")
	assert_false(globe.is_processing(), "an idle globe is not processed every frame")

func test_zoom_is_clamped_to_its_limits() -> void:
	var globe := _make_globe()
	for i in range(20):
		globe.zoom_in()
		globe._process(1.0)
	assert_almost_eq(globe._radius_scale, GlobeMap.MAX_RADIUS_SCALE, 0.0001, "zoom in stops at the limit")
	for i in range(40):
		globe.zoom_out()
		globe._process(1.0)
	assert_almost_eq(globe._radius_scale, GlobeMap.MIN_RADIUS_SCALE, 0.0001, "zoom out stops at the limit")

func test_a_flick_keeps_the_globe_spinning_then_settles() -> void:
	var globe := _make_globe()
	globe.set_view_state({"center_lon": 0.0, "center_lat": 0.0, "radius_scale": 1.0})
	globe._remember_flick(Vector2(900.0, 0.0))
	assert_almost_eq(globe._spin_lon, GlobeMap.MAX_SPIN_DEG_PER_SEC, 0.001, "a hard throw is capped")
	globe._spin_lon = 200.0
	globe.set_process(true)
	var start := globe._center_lon
	for i in range(60):
		globe._process(0.05)
	assert_gt(globe._center_lon, start, "the flick carries the globe onwards")
	assert_lt(absf(globe._spin_lon), 1.0, "and bleeds off")
	assert_false(globe.is_processing(), "a settled globe stops processing")

func test_view_state_round_trips_and_clamps() -> void:
	var globe := _make_globe()
	globe.set_view_state({"center_lon": 42.0, "center_lat": 500.0, "radius_scale": 99.0})
	var state := globe.get_view_state()
	assert_almost_eq(state["center_lon"], 42.0, 0.001, "longitude is kept")
	assert_almost_eq(state["center_lat"], GlobeMap.MAX_CENTER_LAT, 0.001, "latitude is clamped at the poles")
	assert_almost_eq(state["radius_scale"], GlobeMap.MAX_RADIUS_SCALE, 0.001, "zoom is clamped")

## ── Shader contract ──────────────────────────────────────────────────────

func test_the_planet_shader_stays_in_step_with_the_script() -> void:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	assert_false(source.is_empty(), "the globe shader is on disk and readable")
	assert_true(source.contains("shader_type canvas_item;"), "the shader is a canvas item shader")
	assert_true(source.contains("void fragment()"), "the shader has a fragment stage")
	assert_eq(source.count("{"), source.count("}"), "the shader's braces balance")
	assert_eq(source.count("("), source.count(")"), "the shader's parentheses balance")

	var declared := _declared_uniforms(source)
	for uniform_name in SCRIPT_UNIFORMS:
		assert_true(declared.has(uniform_name),
			"the shader declares %s, which GlobeMap sets by name" % uniform_name)
		assert_true(source.count(uniform_name) > 1, "the shader actually uses %s" % uniform_name)
	assert_true(declared.size() >= SCRIPT_UNIFORMS.size(), "the palette and lighting are tunable as uniforms")

## ── The shader's projection must match the pins' ─────────────────────────

## The planet shader unprojects a screen pixel back to a lon/lat and samples
## the land mask there, while the pins are placed by `GlobeMap.project_point`.
## The two have to be exact inverses: if they are not, the mask renders
## mirrored and the pins slide off their destinations as the globe turns.
##
## A shader cannot run headless, so this reads the sign the shader gives the
## screen-space vertical axis straight out of the shader source and feeds it
## through the shader's own inverse formula — the test fails if either the
## sign or the formula stops matching the script's projection.
func test_the_shader_inverts_the_projection_the_pins_are_drawn_with() -> void:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	var y_sign := _shader_vertical_sign(source)
	assert_ne(y_sign, 0.0, "the shader still builds its surface normal from p.x / radius and p.y / radius")

	var worst := 0.0
	var checked := 0
	for view in [[-40.0, 30.0], [-40.0, 0.0], [120.0, -40.0], [0.0, 78.0], [0.0, -78.0]]:
		for spot in [[-4.2, 56.5], [139.7, 35.7], [133.0, -25.0], [-121.9, 36.6], [24.0, -30.0]]:
			var v := GlobeMap.project_point(spot[0], spot[1], view[0], view[1])
			if v.z <= 0.0:
				continue
			# The pixel the script puts the pin on (see _screen_for), turned
			# back into the surface normal exactly as the shader builds it.
			var p := Vector2(v.x, -v.y) * 400.0
			var normal := Vector3(p.x / 400.0, y_sign * p.y / 400.0,
				sqrt(maxf(0.0, 1.0 - p.length_squared() / (400.0 * 400.0))))
			var recovered := _shader_recover_lon_lat(normal, view[0], view[1])
			var lon_error := absf(fposmod(recovered.x - spot[0] + 180.0, 360.0) - 180.0)
			worst = maxf(worst, maxf(lon_error, absf(recovered.y - spot[1])))
			checked += 1
	assert_gt(checked, 10, "enough destinations and view centres were actually on the near side")
	assert_lt(worst, 0.01, "the shader recovers the exact lon/lat the pin was projected from")

func test_the_shader_treats_screen_down_as_south() -> void:
	# Screen +y grows downwards, the globe's +y grows up. Dropping this minus
	# is what mirrored the planet and made the pins drift, so spell it out:
	# the shader must negate the screen-space vertical axis.
	assert_eq(_shader_vertical_sign(FileAccess.get_file_as_string(SHADER_PATH)), -1.0,
		"shaders/globe_planet.gdshader must negate p.y when it builds its surface normal")

## The sign the shader gives the screen-space vertical axis when it builds the
## surface normal, read from the shader so the tests verify what the shader
## actually does. Returns 0.0 if the line is gone, which the tests report.
func _shader_vertical_sign(source: String) -> float:
	for line in source.split("\n"):
		if line.contains("vec3 n = vec3(p.x / radius,"):
			return -1.0 if line.contains("-p.y / radius") else 1.0
	return 0.0

## The shader's lon_lat_for(), as GDScript.
func _shader_recover_lon_lat(n: Vector3, center_lon: float, center_lat: float) -> Vector2:
	n = n.normalized()
	var phi0 := deg_to_rad(center_lat)
	var sin_phi := clampf(n.y * cos(phi0) + n.z * sin(phi0), -1.0, 1.0)
	var lam := atan2(n.x, n.z * cos(phi0) - n.y * sin(phi0))
	return Vector2(rad_to_deg(lam) + center_lon, rad_to_deg(asin(sin_phi)))

func test_the_land_mask_is_sampled_with_wrapping_and_mipmaps() -> void:
	var source := FileAccess.get_file_as_string(SHADER_PATH)
	assert_true(source.contains("uniform sampler2D land_mask : filter_linear_mipmap, repeat_enable"),
		"the mask has to wrap in longitude (the antimeridian) and keep mipmaps for small globes")

func _declared_uniforms(source: String) -> Array:
	var names: Array = []
	for line in source.split("\n"):
		var trimmed := line.strip_edges()
		if not trimmed.begins_with("uniform ") or not trimmed.ends_with(";"):
			continue
		var body := trimmed.substr(8)
		for separator in [":", "="]:
			var at := body.find(separator)
			if at != -1:
				body = body.substr(0, at)
		var parts := body.strip_edges().split(" ", false)
		if parts.size() >= 2:
			names.append(parts[1])
	return names
