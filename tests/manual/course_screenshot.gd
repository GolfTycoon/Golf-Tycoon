extends Node
## Renders a course with a few facilities placed and saves a screenshot.
##
## Run headless with a rendering driver so the viewport has real pixels:
##
##   godot --path . --rendering-driver opengl3 -s tests/manual/course_screenshot.gd
##
## The image lands in `tmp_preview/course.png` (git-ignored). It is a manual
## check for the building pixel art, not part of the test suite.

const OUT := "res://tmp_preview/course.png"


func _ready() -> void:
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp_preview"))
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	add_child(main)
	await get_tree().process_frame
	await get_tree().process_frame

	if main.has_method("start_quick_game"):
		main.start_quick_game()
	await get_tree().create_timer(1.0).timeout
	await get_tree().process_frame

	var entities = main.get("entity_layer")
	var registry: Dictionary = main.get("building_registry")
	var origin := Vector2i(14, 14)
	var layout := [
		["clubhouse", Vector2i(10, 10), 1],
		["pro_shop", Vector2i(15, 10), 1],
		["snack_bar", Vector2i(15, 13), 1],
		["putting_green", Vector2i(10, 15), 1],
		["cart_garage", Vector2i(18, 12), 1],
		["resort_hotel", Vector2i(18, 15), 1],
		["tennis_court", Vector2i(11, 19), 1],
		["theme_park", Vector2i(20, 8), 1],
	]
	if entities and registry:
		for job in layout:
			var building = entities.place_building(job[0], job[1], registry)
			if building:
				building.upgrade_level = job[2]
				building._update_visuals()
	if main.has_method("focus_camera_on"):
		main.focus_camera_on(origin)
	var camera = main.get("camera")
	if camera:
		camera.global_position = Vector2(origin.x * 32 - origin.y * 32, origin.x * 16 + origin.y * 16)
		camera.set_zoom_level(1.2, true)

	for i in range(20):
		await get_tree().process_frame
	await get_tree().create_timer(0.5).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	if image:
		image.save_png(OUT)
		print("saved ", OUT)
	get_tree().quit()
