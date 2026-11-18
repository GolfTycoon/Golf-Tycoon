shader_type canvas_item;

// A facility's pixel art, standing on its footprint. Buildings keep their place
// in the entity Y-sort, but a terrain surface nearer the camera clips their
// pixels, as it clips trees (terrain_sprite_occlusion.gdshader).
//
// A tree is a thin billboard on one ground point; a building is a solid on a
// rectangle of tiles, so one anchor cannot describe it: anchored at its centre,
// its own level foundation would clip the walls in front of that centre. Every
// pixel of the art shows a point inside the footprint's column, and the only
// terrain inside that column is the level foundation under it, so terrain can
// only be in front of the building where it is in front of the column. The test
// therefore compares the terrain with the column's front face along each pixel's
// ray, which is exact for any shape the art has inside its footprint.
uniform sampler2D vertex_elevation : filter_linear, repeat_disable;
uniform vec2 vertex_grid_size = vec2(129.0);
uniform vec2 grid_size = vec2(128.0);
uniform float elevation_step_y = 10.0;
uniform float elevation_texture_zero = 128.0;
uniform float elevation_texture_scale = 25.0;
uniform bool is_isometric = true;
uniform vec2 grid_origin = vec2(0.0);
uniform vec2 grid_axis_x = vec2(64.0, 32.0);
uniform vec2 grid_axis_y = vec2(0.0, 32.0);

// The tiles the building stands on: the grid corner of its origin tile, and its
// width and depth in tiles.
uniform vec2 footprint_position = vec2(0.0);
uniform vec2 footprint_size = vec2(1.0);
uniform float occlusion_epsilon = 0.05;

#include "res://shaders/terrain_heightfield.gdshaderinc"

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

// The ray parameter at which this pixel's ray reaches the footprint's column from
// the camera side: the front face of the building's volume. A pixel beside the
// column (art overhanging the footprint) continues smoothly from its edge.
float footprint_front_t(vec2 world) {
	vec2 flat_point = world_to_grid(world);
	vec2 ray_direction = world_to_grid(world + vec2(0.0, 1.0)) - flat_point;
	float enter_t = -ELEVATION_RAY_NO_ROOT;
	float leave_t = ELEVATION_RAY_NO_ROOT;
	for (int axis = 0; axis < 2; axis++) {
		float direction = ray_direction[axis];
		if (abs(direction) < 0.000001) {
			// The ray runs along this side of the footprint: the other axis alone
			// says where it meets the column.
			continue;
		}
		float side_a = (footprint_position[axis] - flat_point[axis]) / direction;
		float side_b = (footprint_position[axis] + footprint_size[axis] - flat_point[axis]) / direction;
		enter_t = max(enter_t, min(side_a, side_b));
		leave_t = min(leave_t, max(side_a, side_b));
	}
	return enter_t <= leave_t ? leave_t : 0.5 * (enter_t + leave_t);
}

void fragment() {
	// Only whether the pixel is drawn is decided here. Godot 4 has already
	// multiplied the texture into the colour this function receives, so the art
	// is left exactly as drawn: sampling the texture again would square every
	// channel and darken it.
	//
	// The foundation is level, so its centre is its height. Art that hangs below
	// the footprint's front edge stands on that ground rather than under it.
	vec2 footprint_centre = footprint_position + footprint_size * 0.5;
	float base_t = elevation_at_grid(footprint_centre) * elevation_step_y;
	float building_t = max(base_t, footprint_front_t(world_position));
	if (terrain_hides(world_position, building_t + occlusion_epsilon)) {
		discard;
	}
}
