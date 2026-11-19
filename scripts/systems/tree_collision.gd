extends RefCounted
class_name TreeCollision
## Fast, rotation-invariant 2.5D ball-vs-tree-sprite collision solver for both
## airborne shot trajectories and ground rollouts.
##
## Uses lazy-cached 2px sprite masks (`TreeCollisionProfile`) and deterministic
## per-tile layout (`TreeOverlay.variation_for_tile`, `facing_at`, `species_at`)
## so open shots incur near-zero overhead and wooded shots match visible sprites.

const BALL_FLIGHT_RADIUS_PX: float = 2.2
const BALL_ROLL_RADIUS_PX: float = 2.6
const MAX_FLIGHT_HITS: int = 3
const MAX_ROLL_HITS: int = 3
const FLIGHT_STEP_PX: float = 4.0
const SELF_TILE_ESCAPE_TILES: float = 0.72
const SAME_TREE_REHIT_ISO_PX: float = 18.0
## Isometric ground scaling factor: `tile_width / (2 * tile_height)` = 2.0 for 64x32.
const ISO_Y_SCALE: float = 2.0
## Standard 45-deg isometric ground scale: 32 * sqrt(2) px per tile.
const PX_PER_TILE: float = 45.254834


## Collect all tree tile coordinates inside a tight corridor around segment
## `[from_p, to_p]`, visiting every candidate tile at most once without heap sets.
static func collect_trees_along_segment(grid: TerrainGrid, from_p: Vector2, to_p: Vector2,
		pad_tiles: float = 1.6) -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	if grid == null or grid.grid_width <= 0 or grid.grid_height <= 0:
		return result

	var delta := to_p - from_p
	if absf(delta.x) >= absf(delta.y):
		var min_x := clampi(floori(minf(from_p.x, to_p.x) - pad_tiles), 0, grid.grid_width - 1)
		var max_x := clampi(ceili(maxf(from_p.x, to_p.x) + pad_tiles), 0, grid.grid_width - 1)
		var min_y_all := clampi(floori(minf(from_p.y, to_p.y) - pad_tiles), 0, grid.grid_height - 1)
		var max_y_all := clampi(ceili(maxf(from_p.y, to_p.y) + pad_tiles), 0, grid.grid_height - 1)
		var inv_dx := 1.0 / delta.x if absf(delta.x) > 0.0001 else 0.0
		for tx in range(min_x, max_x + 1):
			var cy := (from_p.y + to_p.y) * 0.5
			if inv_dx != 0.0:
				var t_val := clampf((float(tx) + 0.5 - from_p.x) * inv_dx, 0.0, 1.0)
				cy = lerpf(from_p.y, to_p.y, t_val)
			var half_band := pad_tiles + absf(delta.y * inv_dx) * 0.6 if inv_dx != 0.0 else pad_tiles + absf(delta.y) * 0.5
			var y0 := maxi(min_y_all, floori(cy - half_band))
			var y1 := mini(max_y_all, ceili(cy + half_band))
			for ty in range(y0, y1 + 1):
				var pos := Vector2i(tx, ty)
				if TerrainTypes.is_tree(grid.get_tile(pos)):
					result.append(pos)
	else:
		var min_y := clampi(floori(minf(from_p.y, to_p.y) - pad_tiles), 0, grid.grid_height - 1)
		var max_y := clampi(ceili(maxf(from_p.y, to_p.y) + pad_tiles), 0, grid.grid_height - 1)
		var min_x_all := clampi(floori(minf(from_p.x, to_p.x) - pad_tiles), 0, grid.grid_width - 1)
		var max_x_all := clampi(ceili(maxf(from_p.x, to_p.x) + pad_tiles), 0, grid.grid_width - 1)
		var inv_dy := 1.0 / delta.y if absf(delta.y) > 0.0001 else 0.0
		for ty in range(min_y, max_y + 1):
			var cx := (from_p.x + to_p.x) * 0.5
			if inv_dy != 0.0:
				var t_val := clampf((float(ty) + 0.5 - from_p.y) * inv_dy, 0.0, 1.0)
				cx = lerpf(from_p.x, to_p.x, t_val)
			var half_band := pad_tiles + absf(delta.x * inv_dy) * 0.6 if inv_dy != 0.0 else pad_tiles + absf(delta.x) * 0.5
			var x0 := maxi(min_x_all, floori(cx - half_band))
			var x1 := mini(max_x_all, ceili(cx + half_band))
			for tx in range(x0, x1 + 1):
				var pos := Vector2i(tx, ty)
				if TerrainTypes.is_tree(grid.get_tile(pos)):
					result.append(pos)
	return result


## Build lightweight collision descriptor for one tree tile.
static func _build_tree_info(grid: TerrainGrid, tile: Vector2i, elev_step_y: float,
		base_elev: int) -> Dictionary:
	var tile_type := grid.get_tile(tile)
	var species := TreeOverlay.species_at(tile_type, tile)
	var facing := TreeOverlay.facing_at(tile)
	var profile := TreeCollisionProfile.get_profile_for_tile(grid, tile, species, facing)
	var variation := TreeOverlay.variation_for_tile(tile)
	var scale_v: float = variation.scale
	var jitter: Vector2 = variation.jitter
	# Anchor jitter on the terrain tile (canonical ori=0 plane -> grid) so tree
	# world position stays fixed under camera rotation.
	var jitter_grid := Vector2(
		jitter.x / float(grid.tile_width) + jitter.y / float(grid.tile_height),
		jitter.y / float(grid.tile_height) - jitter.x / float(grid.tile_width)
	)
	var plane := grid.projection.project(Vector2(tile) + Vector2(0.5, 0.5) + jitter_grid)
	var alt := float(grid.get_tile_height(tile) - base_elev) * elev_step_y
	var max_r := profile.max_abs_dx * scale_v + BALL_ROLL_RADIUS_PX + 2.0
	var max_h := profile.max_world_h * scale_v + absf(profile.post_offset.y) + 2.0
	return {
		"tile": tile,
		"species": species,
		"profile": profile,
		"scale": scale_v,
		"jitter": jitter,
		"plane": plane,
		"alt": alt,
		"max_r_sq": max_r * max_r,
		"max_h": max_h,
	}


## Convert an isotropic 2D pixel delta (where `x = plane.x`, `z = 2 * plane.y`)
## back to a continuous grid-coordinate delta independent of camera orientation.
static func _iso_delta_to_grid(grid: TerrainGrid, iso_delta: Vector2) -> Vector2:
	var plane_delta := Vector2(iso_delta.x, iso_delta.y / ISO_Y_SCALE)
	var p0 := grid.projection.project(Vector2.ZERO)
	# Screen-to-grid using exact projection axes by inverting 2x2 basis on unit vectors.
	var ex := grid.projection.project(Vector2(1.0, 0.0)) - p0
	var ey := grid.projection.project(Vector2(0.0, 1.0)) - p0
	var det := ex.x * ey.y - ex.y * ey.x
	if absf(det) < 0.0001:
		return Vector2.ZERO
	var gx := (plane_delta.x * ey.y - plane_delta.y * ey.x) / det
	var gy := (ex.x * plane_delta.y - ex.y * plane_delta.x) / det
	return Vector2(gx, gy)


static func _grid_delta_to_iso(grid: TerrainGrid, grid_delta: Vector2) -> Vector2:
	var p := grid.projection.project(grid_delta) - grid.projection.project(Vector2.ZERO)
	return Vector2(p.x, p.y * ISO_Y_SCALE)


static func _iso_dist(grid: TerrainGrid, a: Vector2, b: Vector2) -> float:
	return _grid_delta_to_iso(grid, b - a).length()


## Simulate continuous 2.5D tree collisions along an airborne shot trajectory.
## Returns:
## {
##   "hit": bool,
##   "carry": Vector2,
##   "segments": Array[Dictionary],
##   "first_hit_tile": Vector2i,
##   "first_hit_species": String,
##   "first_hit_material": int,
##   "first_hit_ground": Vector2,
##   "first_hit_height": float,
##   "roll_dir_override": Vector2 (if bounced, last velocity direction),
##   "speed_factor": float (residual speed scale for post-bounce rollout),
## }
static func simulate_flight(grid: TerrainGrid, from_p: Vector2, carry_raw: Vector2,
		flight_max_height: float, bend_grid: Vector2, wind_grid: Vector2,
		club: int, deterministic: bool) -> Dictionary:
	if grid == null or from_p.distance_to(carry_raw) < 0.05:
		return {"hit": false, "carry": carry_raw, "segments": []}

	var elev_step_y: float = grid.ELEVATION_STEP_Y
	var base_elev: int = grid.BASE_ELEVATION
	var start_tile := Vector2i(from_p.round())

	var segments: Array[Dictionary] = []
	var leg_from := from_p
	var leg_to := carry_raw
	var leg_start_h := 0.0
	var leg_pop_h := flight_max_height
	var leg_bend := bend_grid
	var leg_wind := wind_grid

	var hit_any := false
	var first_hit_tile := Vector2i(-1, -1)
	var first_hit_species := ""
	var first_hit_material := TreeCollisionProfile.MAT_EMPTY
	var first_hit_ground := carry_raw
	var first_hit_height := 0.0
	var last_hit_tile := Vector2i(-999, -999)
	var residual_speed_factor := 1.0
	var final_dir := (carry_raw - from_p).normalized()

	var tree_cache: Dictionary = {}

	for leg_idx in range(MAX_FLIGHT_HITS + 1):
		var swell_pad := maxf(leg_bend.length(), 0.0) + maxf(leg_wind.length(), 0.0) + 1.6
		var candidate_tiles := collect_trees_along_segment(grid, leg_from, leg_to, swell_pad)
		var iso_len := _iso_dist(grid, leg_from, leg_to)
		if candidate_tiles.is_empty() or iso_len < 1.0 or leg_idx == MAX_FLIGHT_HITS:
			segments.append({
				"from": leg_from,
				"to": leg_to,
				"start_h": leg_start_h,
				"end_h": 0.0,
				"pop_h": leg_pop_h,
				"phase_from": 0.0,
				"phase_to": 1.0,
				"bend_grid": leg_bend,
				"wind_grid": leg_wind,
				"duration_weight": maxf(iso_len, 8.0),
				"hit_at_end": false,
			})
			break

		var trees: Array[Dictionary] = []
		var global_max_h := 0.0
		for tile in candidate_tiles:
			if not tree_cache.has(tile):
				tree_cache[tile] = _build_tree_info(grid, tile, elev_step_y, base_elev)
			var info: Dictionary = tree_cache[tile]
			trees.append(info)
			if info.max_h > global_max_h:
				global_max_h = info.max_h

		var num_steps := clampi(ceili(iso_len / FLIGHT_STEP_PX), 6, 280)
		var hit_found := false
		var hit_s := 1.0
		var hit_pos_g := leg_to
		var hit_h := 0.0
		var hit_tree: Dictionary = {}
		var hit_mat := TreeCollisionProfile.MAT_EMPTY
		var hit_vel_iso := Vector2.ZERO
		var prev_pos_g := leg_from

		for step in range(1, num_steps + 1):
			var s := float(step) / float(num_steps)
			var swell := sin(s * PI)
			var pos_g := leg_from.lerp(leg_to, s) + (leg_bend + leg_wind) * swell
			var ball_h := lerpf(leg_start_h, 0.0, s) + swell * leg_pop_h

			# Fast vertical early-out when flying over every candidate canopy.
			if ball_h <= global_max_h + BALL_FLIGHT_RADIUS_PX + 24.0:
				var ball_plane := grid.projection.project(pos_g + Vector2(0.5, 0.5))
				var ball_alt := (grid.get_elevation_at_precise(pos_g) - float(base_elev)) * elev_step_y + ball_h
				var dist_along_leg := s * iso_len

				for tree in trees:
					var t_tile: Vector2i = tree.tile
					if leg_idx == 0 and t_tile == start_tile and pos_g.distance_to(leg_from) < SELF_TILE_ESCAPE_TILES:
						continue
					if t_tile == last_hit_tile and dist_along_leg < SAME_TREE_REHIT_ISO_PX:
						continue

					var dx: float = ball_plane.x - tree.plane.x
					var dy: float = ball_plane.y - tree.plane.y
					var iso_z := dy * ISO_Y_SCALE
					var r_iso_sq := dx * dx + iso_z * iso_z
					if r_iso_sq > tree.max_r_sq:
						continue

					var h: float = ball_alt - tree.alt + tree.jitter.y
					if h < -2.0 or h > tree.max_h + BALL_FLIGHT_RADIUS_PX:
						continue

					var prof: TreeCollisionProfile = tree.profile
					var sc: float = tree.scale
					var row_hw := prof.half_width_at_height(maxf(h, 0.0), sc)
					if row_hw <= 0.0:
						continue
					var effective_r := maxf(row_hw, 3.0) + BALL_FLIGHT_RADIUS_PX
					if r_iso_sq > effective_r * effective_r:
						continue

					var mat := prof.sample_radial(sqrt(r_iso_sq), h, BALL_FLIGHT_RADIUS_PX, sc)
					if mat != TreeCollisionProfile.MAT_EMPTY:
						hit_found = true
						hit_s = s
						hit_pos_g = pos_g
						hit_h = ball_h
						hit_tree = tree
						hit_mat = mat
						hit_vel_iso = _grid_delta_to_iso(grid, pos_g - prev_pos_g)
						break

			if hit_found:
				break
			prev_pos_g = pos_g

		if not hit_found:
			segments.append({
				"from": leg_from,
				"to": leg_to,
				"start_h": leg_start_h,
				"end_h": 0.0,
				"pop_h": leg_pop_h,
				"phase_from": 0.0,
				"phase_to": 1.0,
				"bend_grid": leg_bend,
				"wind_grid": leg_wind,
				"duration_weight": maxf(iso_len, 8.0),
				"hit_at_end": false,
			})
			break

		# Record first hit details.
		hit_any = true
		if first_hit_material == TreeCollisionProfile.MAT_EMPTY:
			first_hit_tile = hit_tree.tile
			first_hit_species = hit_tree.species
			first_hit_material = hit_mat
			first_hit_ground = hit_pos_g
			first_hit_height = hit_h

		# Clamp impact tile onto valid grid if near rim.
		if not grid.is_valid_position(Vector2i(hit_pos_g.round())):
			hit_pos_g = leg_from.lerp(hit_pos_g, 0.95)

		segments.append({
			"from": leg_from,
			"to": hit_pos_g,
			"start_h": leg_start_h,
			"end_h": hit_h,
			"pop_h": leg_pop_h,
			"phase_from": 0.0,
			"phase_to": hit_s,
			"bend_grid": leg_bend,
			"wind_grid": leg_wind,
			"duration_weight": maxf(iso_len * hit_s, 6.0),
			"hit_at_end": true,
			"hit_tree_tile": hit_tree.tile,
			"hit_species": hit_tree.species,
			"hit_material": hit_mat,
		})

		# Compute deflection / drop response for next flight segment.
		var remaining_iso := maxf(iso_len * (1.0 - hit_s), 12.0)
		if hit_vel_iso.length_squared() < 0.0001:
			hit_vel_iso = _grid_delta_to_iso(grid, leg_to - leg_from)
		var vel_dir_iso := hit_vel_iso.normalized()
		var ball_plane_hit := grid.projection.project(hit_pos_g + Vector2(0.5, 0.5))
		var radial_iso := Vector2(
			ball_plane_hit.x - hit_tree.plane.x,
			(ball_plane_hit.y - hit_tree.plane.y) * ISO_Y_SCALE
		)
		var normal_iso: Vector2
		if radial_iso.length_squared() < 2.0:
			# Dead-center hit: reflect almost back with a subtle deterministic or random nudge.
			var side := 0.0 if deterministic else randf_range(-0.35, 0.35)
			if deterministic:
				side = 0.18 if ((hit_tree.tile.x + hit_tree.tile.y) % 2 == 0) else -0.18
			var perp := Vector2(-vel_dir_iso.y, vel_dir_iso.x)
			normal_iso = (-vel_dir_iso + perp * side).normalized()
		else:
			normal_iso = radial_iso.normalized()
			if normal_iso.dot(vel_dir_iso) > 0.0:
				# Grazing back-side exit: orient normal cleanly outward.
				normal_iso = (normal_iso - vel_dir_iso * 0.5).normalized()

		var next_dir_iso: Vector2
		var next_dist_iso: float
		var next_pop_h: float

		match hit_mat:
			TreeCollisionProfile.MAT_WOOD:
				next_dir_iso = vel_dir_iso.bounce(normal_iso).normalized()
				if not deterministic:
					next_dir_iso = next_dir_iso.rotated(deg_to_rad(randf_range(-6.0, 6.0)))
				var bounce_frac := 0.45 if deterministic else randf_range(0.38, 0.54)
				next_dist_iso = clampf(remaining_iso * bounce_frac, 0.55 * PX_PER_TILE, 4.2 * PX_PER_TILE)
				next_pop_h = clampf(next_dist_iso * 0.12, 5.0, 20.0)
				residual_speed_factor *= 0.45

			TreeCollisionProfile.MAT_FOLIAGE:
				# Outer fringe clip on a fast club partially punches through; deep hit drops steeply.
				var hit_profile: TreeCollisionProfile = hit_tree.profile
				var hit_scale: float = hit_tree.scale
				var hw_here: float = hit_profile.half_width_at_height(maxf(hit_h, 0.0), hit_scale)
				var is_fringe: bool = hw_here > 10.0 and (
					radial_iso.length() >= hw_here * 0.68
					or hit_h >= float(hit_tree.max_h) * 0.78
				)
				var fast_club := club in [0, 1, 2]  # DRIVER / FW / IRON
				if is_fringe and fast_club and remaining_iso > 2.5 * PX_PER_TILE:
					var deflect := 0.0 if deterministic else deg_to_rad(randf_range(-12.0, 12.0))
					var nudge_side := signf(vel_dir_iso.x * normal_iso.y - vel_dir_iso.y * normal_iso.x)
					next_dir_iso = vel_dir_iso.rotated(-nudge_side * 0.16 + deflect).normalized()
					next_dist_iso = clampf(remaining_iso * 0.52, 0.8 * PX_PER_TILE, 6.0 * PX_PER_TILE)
					next_pop_h = clampf(next_dist_iso * 0.05, 1.0, 8.0)
					residual_speed_factor *= 0.55
				else:
					# Deep foliage drop: trickle down just outside the trunk radius.
					var out_blend := normal_iso.lerp(vel_dir_iso, 0.35).normalized()
					if not deterministic:
						out_blend = out_blend.rotated(deg_to_rad(randf_range(-20.0, 20.0)))
					next_dir_iso = out_blend
					next_dist_iso = clampf(remaining_iso * 0.18, 0.42 * PX_PER_TILE, 1.6 * PX_PER_TILE)
					next_pop_h = 2.0
					residual_speed_factor *= 0.25

			_:  # MAT_BRUSH
				next_dir_iso = vel_dir_iso.lerp(normal_iso, 0.25).normalized()
				next_dist_iso = clampf(remaining_iso * 0.14, 0.25 * PX_PER_TILE, 0.75 * PX_PER_TILE)
				next_pop_h = 1.5
				residual_speed_factor *= 0.20

		var next_delta_g := _iso_delta_to_grid(grid, next_dir_iso * next_dist_iso)
		var next_target := hit_pos_g + next_delta_g
		if not grid.is_valid_position(Vector2i(next_target.round())):
			# Clamp bounce inside playable grid bounds safely.
			next_target.x = clampf(next_target.x, 0.0, float(grid.grid_width - 1))
			next_target.y = clampf(next_target.y, 0.0, float(grid.grid_height - 1))

		last_hit_tile = hit_tree.tile
		leg_from = hit_pos_g
		leg_to = next_target
		leg_start_h = hit_h
		leg_pop_h = next_pop_h
		leg_bend = Vector2.ZERO
		leg_wind = Vector2.ZERO
		if next_delta_g.length_squared() > 0.0001:
			final_dir = next_delta_g.normalized()

	var final_carry: Vector2 = segments[segments.size() - 1].to if not segments.is_empty() else carry_raw
	return {
		"hit": hit_any,
		"carry": final_carry,
		"segments": segments,
		"first_hit_tile": first_hit_tile,
		"first_hit_species": first_hit_species,
		"first_hit_material": first_hit_material,
		"first_hit_ground": first_hit_ground,
		"first_hit_height": first_hit_height,
		"final_dir": final_dir,
		"speed_factor": residual_speed_factor,
	}


## Check one ground rollout step `[prev_p, next_p]` against visible tree trunks,
## low conifer skirts, and brush at ground level (`h = 0`).
## Returns `{hit: bool, hit_pos, new_dir, damp, tree_tile, species, material}`.
static func check_roll_step(grid: TerrainGrid, prev_p: Vector2, next_p: Vector2,
		roll_dir: Vector2, start_tile: Vector2i, recent_hit_tile: Vector2i,
		tree_cache: Dictionary, deterministic: bool) -> Dictionary:
	if grid == null:
		return {"hit": false}
	var candidates := collect_trees_along_segment(grid, prev_p, next_p, 1.1)
	if candidates.is_empty():
		return {"hit": false}

	var elev_step_y: float = grid.ELEVATION_STEP_Y
	var base_elev: int = grid.BASE_ELEVATION
	var ball_plane := grid.projection.project(next_p + Vector2(0.5, 0.5))
	var ball_alt := (grid.get_elevation_at_precise(next_p) - float(base_elev)) * elev_step_y

	for tile in candidates:
		if tile == start_tile and next_p.distance_to(Vector2(start_tile)) < SELF_TILE_ESCAPE_TILES:
			continue
		if tile == recent_hit_tile and next_p.distance_to(Vector2(recent_hit_tile)) < 0.65:
			continue
		if not tree_cache.has(tile):
			tree_cache[tile] = _build_tree_info(grid, tile, elev_step_y, base_elev)
		var tree: Dictionary = tree_cache[tile]
		var dx: float = ball_plane.x - tree.plane.x
		var dy: float = ball_plane.y - tree.plane.y
		var iso_z := dy * ISO_Y_SCALE
		var r_iso_sq := dx * dx + iso_z * iso_z
		if r_iso_sq > tree.max_r_sq:
			continue

		var h: float = ball_alt - tree.alt + tree.jitter.y
		if absf(h) > 10.0:
			continue

		var prof: TreeCollisionProfile = tree.profile
		var sc: float = tree.scale
		# Sample near ground contact (0..3px above ground).
		var sample_h := maxf(h, 2.0)
		var row_hw := prof.half_width_at_height(sample_h, sc)
		if row_hw <= 0.0:
			continue
		var eff_r := maxf(row_hw, 3.0) + BALL_ROLL_RADIUS_PX
		if r_iso_sq > eff_r * eff_r:
			continue

		var mat := prof.sample_radial(sqrt(r_iso_sq), sample_h, BALL_ROLL_RADIUS_PX, sc)
		if mat == TreeCollisionProfile.MAT_EMPTY:
			continue

		var dir_iso := _grid_delta_to_iso(grid, roll_dir)
		if dir_iso.length_squared() < 0.0001:
			dir_iso = Vector2(1.0, 0.0)
		dir_iso = dir_iso.normalized()
		var radial_iso := Vector2(dx, iso_z)
		var normal_iso := radial_iso.normalized() if radial_iso.length_squared() > 1.0 else -dir_iso
		if normal_iso.dot(dir_iso) > 0.0:
			normal_iso = -dir_iso

		var new_dir := roll_dir
		var damp := 0.5
		if mat == TreeCollisionProfile.MAT_WOOD:
			var refl_iso := dir_iso.bounce(normal_iso).normalized()
			if not deterministic:
				refl_iso = refl_iso.rotated(deg_to_rad(randf_range(-5.0, 5.0)))
			new_dir = _iso_delta_to_grid(grid, refl_iso).normalized()
			damp = 0.45
		elif mat == TreeCollisionProfile.MAT_FOLIAGE:
			var side := signf(dir_iso.x * normal_iso.y - dir_iso.y * normal_iso.x)
			var defl_iso := dir_iso.rotated(-side * 0.25).normalized()
			new_dir = _iso_delta_to_grid(grid, defl_iso).normalized()
			damp = 0.45
		else:  # MAT_BRUSH
			damp = 0.25

		return {
			"hit": true,
			"hit_pos": prev_p.lerp(next_p, 0.5),
			"new_dir": new_dir if new_dir.length_squared() > 0.0001 else -roll_dir,
			"damp": damp,
			"tree_tile": tile,
			"species": tree.species,
			"material": mat,
		}

	return {"hit": false}
