shader_type canvas_item;

// Heightfield data shared with CourseSurface. Sprite pixels stay in the normal
// entity Y-sort, but a terrain surface nearer the camera clips them per pixel.
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

// Ground point in grid coordinates and its small deterministic screen jitter.
uniform vec2 ground_grid = vec2(0.5);
uniform vec2 ground_offset = vec2(0.0);
uniform float occlusion_epsilon = 0.05;

#include "res://shaders/terrain_heightfield.gdshaderinc"

varying vec2 world_position;

void vertex() {
	world_position = (MODEL_MATRIX * vec4(VERTEX, 0.0, 1.0)).xy;
}

void fragment() {
	vec4 sprite_color = texture(TEXTURE, UV) * COLOR;

	// A vertical sprite pixel above its ground anchor raises its position along
	// the same screen-space ray parameter used by the terrain intersection.
	float ground_t = elevation_at_grid(ground_grid) * elevation_step_y;
	vec2 ground_world = grid_origin + ground_grid.x * grid_axis_x
		+ ground_grid.y * grid_axis_y + ground_offset;
	ground_world.y -= ground_t;
	float sprite_t = ground_t + ground_world.y - world_position.y;

	bool terrain_hit;
	vec2 terrain_point = surface_grid_at_world(world_position, terrain_hit);
	if (terrain_hit) {
		float terrain_t = elevation_at_grid(terrain_point) * elevation_step_y;
		if (terrain_t > sprite_t + occlusion_epsilon) {
			discard;
		}
	}
	COLOR = sprite_color;
}
