// Shared screen-space heightfield projection. The including shader must declare
// vertex_elevation, vertex_grid_size, grid_size, elevation_step_y,
// elevation_texture_zero/scale, is_isometric, grid_origin and grid_axis_x/y.
// Keeping picking and sprite occlusion on this same intersection prevents a
// hill from disagreeing with the ground about which surface is in front.

vec2 world_to_grid(vec2 world) {
	vec2 d = world - grid_origin;
	float det = grid_axis_x.x * grid_axis_y.y - grid_axis_y.x * grid_axis_x.y;
	if (abs(det) < 0.000001) {
		return vec2(-1.0);
	}
	return vec2(
		(d.x * grid_axis_y.y - grid_axis_y.x * d.y) / det,
		(grid_axis_x.x * d.y - grid_axis_x.y * d.x) / det);
}

float elevation_at_grid(vec2 g) {
	// Clamp only the height lookup. Ray intersections are separately clipped to
	// the actual course, while normals at the rim use the rim's height just as
	// TerrainGrid.get_elevation_at() does.
	vec2 uv = (clamp(g, vec2(0.0), grid_size) + 0.5) / vertex_grid_size;
	return (texture(vertex_elevation, uv).r * 255.0 - elevation_texture_zero)
		/ elevation_texture_scale;
}

const int ELEVATION_RAY_MAX_TILE_STEPS = 12;
const float ELEVATION_RAY_EPSILON = 0.00001;
const float ELEVATION_RAY_NO_ROOT = 1.0e20;

float elevation_at_vertex(vec2 vertex) {
	vec2 uv = (clamp(vertex, vec2(0.0), grid_size) + 0.5) / vertex_grid_size;
	return (texture(vertex_elevation, uv).r * 255.0 - elevation_texture_zero)
		/ elevation_texture_scale;
}

float elevation_ray_value(float t, vec2 g) {
	return t - elevation_at_grid(g) * elevation_step_y;
}

// Return the greatest root in [low_t, high_t], or NO_ROOT when this tile misses.
// Height is bilinear in a tile, so the ray/height difference is quadratic.
float intersect_elevation_tile(vec2 flat_point, vec2 ray_direction, vec2 cell,
		float high_t, float low_t, float middle_t) {
	float h00 = elevation_at_vertex(cell);
	float h10 = elevation_at_vertex(cell + vec2(1.0, 0.0));
	float h01 = elevation_at_vertex(cell + vec2(0.0, 1.0));
	float h11 = elevation_at_vertex(cell + vec2(1.0, 1.0));
	float hx = h10 - h00;
	float hy = h01 - h00;
	float hxy = h11 - h10 - h01 + h00;
	vec2 middle_point = flat_point + ray_direction * middle_t;
	float u = middle_point.x - cell.x;
	float v = middle_point.y - cell.y;
	float c0 = h00 + hx * u + hy * v + hxy * u * v;
	float c1 = hx * ray_direction.x + hy * ray_direction.y
		+ hxy * (u * ray_direction.y + v * ray_direction.x);
	float c2 = hxy * ray_direction.x * ray_direction.y;

	// q = t - middle_t. F(q) = a*q^2 + b*q + c.
	float a = -elevation_step_y * c2;
	float b = 1.0 - elevation_step_y * c1;
	float c = middle_t - elevation_step_y * c0;
	float low_q = low_t - middle_t;
	float high_q = high_t - middle_t;
	float best_q = -ELEVATION_RAY_NO_ROOT;
	if (abs(a) <= ELEVATION_RAY_EPSILON) {
		if (abs(b) <= ELEVATION_RAY_EPSILON) {
			return abs(c) <= ELEVATION_RAY_EPSILON ? high_t : ELEVATION_RAY_NO_ROOT;
		}
		float q = -c / b;
		if (q >= low_q - ELEVATION_RAY_EPSILON && q <= high_q + ELEVATION_RAY_EPSILON) {
			best_q = q;
		}
	} else {
		float discriminant = b * b - 4.0 * a * c;
		if (discriminant >= -ELEVATION_RAY_EPSILON) {
			float root = sqrt(max(0.0, discriminant));
			float q = (-b + root) / (2.0 * a);
			if (q >= low_q - ELEVATION_RAY_EPSILON && q <= high_q + ELEVATION_RAY_EPSILON) {
				best_q = max(best_q, q);
			}
			q = (-b - root) / (2.0 * a);
			if (q >= low_q - ELEVATION_RAY_EPSILON && q <= high_q + ELEVATION_RAY_EPSILON) {
				best_q = max(best_q, q);
			}
		}
	}
	return best_q > -1.0e19 ? middle_t + best_q : ELEVATION_RAY_NO_ROOT;
}

// Inverse of grid_point_to_screen(): intersect the screen pixel's vertical ray
// with the heightfield. Fixed-point iteration oscillates on cliffs and can select
// a hidden surface; exact tile intersections find the front-most surface instead.
vec2 surface_grid_at_world(vec2 world, out bool hit) {
	vec2 flat_point = world_to_grid(world);
	hit = true;
	if (!is_isometric || elevation_step_y <= 0.0) {
		return flat_point;
	}
	vec2 ray_direction = world_to_grid(world + vec2(0.0, 1.0)) - flat_point;
	float lower_t = -5.0 * elevation_step_y;
	float upper_t = 5.0 * elevation_step_y;
	for (int axis = 0; axis < 2; axis++) {
		float start = flat_point[axis];
		float direction = ray_direction[axis];
		float extent = grid_size[axis];
		if (abs(direction) < 0.000001) {
			if (start < 0.0 || start > extent) {
				hit = false;
				return vec2(-1.0);
			}
			continue;
		}
		float edge_a = -start / direction;
		float edge_b = (extent - start) / direction;
		lower_t = max(lower_t, min(edge_a, edge_b));
		upper_t = min(upper_t, max(edge_a, edge_b));
	}
	if (lower_t > upper_t) {
		hit = false;
		return vec2(-1.0);
	}
	if (abs(upper_t - lower_t) <= ELEVATION_RAY_EPSILON) {
		vec2 rim_point = flat_point + ray_direction * upper_t;
		if (abs(elevation_ray_value(upper_t, rim_point)) <= ELEVATION_RAY_EPSILON) {
			return clamp(rim_point, vec2(0.0), grid_size);
		}
		hit = false;
		return vec2(-1.0);
	}

	// Walk only crossed tiles. Unlike a raymarch, this cannot skip a narrow peak
	// or a tangent contact, and flat pixels usually need only a few tile lookups.
	float current_t = upper_t;
	for (int segment = 0; segment < ELEVATION_RAY_MAX_TILE_STEPS; segment++) {
		vec2 current_point = flat_point + ray_direction * current_t;
		float next_t = lower_t;
		for (int axis = 0; axis < 2; axis++) {
			float direction = ray_direction[axis];
			if (abs(direction) < 0.000001) {
				continue;
			}
			float boundary = direction > 0.0
				? floor(current_point[axis] - ELEVATION_RAY_EPSILON)
				: ceil(current_point[axis] + ELEVATION_RAY_EPSILON);
			float boundary_t = (boundary - flat_point[axis]) / direction;
			if (boundary_t < current_t && boundary_t > next_t) {
				next_t = boundary_t;
			}
		}
		if (next_t >= current_t - ELEVATION_RAY_EPSILON) {
			break;
		}
		float middle_t = (current_t + next_t) * 0.5;
		vec2 middle_point = flat_point + ray_direction * middle_t;
		vec2 cell = floor(middle_point);
		if (all(greaterThanEqual(cell, vec2(0.0))) && all(lessThan(cell, grid_size))) {
			float root_t = intersect_elevation_tile(flat_point, ray_direction, cell,
				current_t, next_t, middle_t);
			if (root_t < ELEVATION_RAY_NO_ROOT) {
				return clamp(flat_point + ray_direction * root_t, vec2(0.0), grid_size);
			}
		}
		if (next_t <= lower_t + ELEVATION_RAY_EPSILON) {
			break;
		}
		current_t = next_t;
	}
	hit = false;
	return vec2(-1.0);
}

