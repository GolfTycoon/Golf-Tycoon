extends SceneTree
## Renders the Visiting Golfers shelf with a few on-course and past visitors
## and saves a screenshot.
##
## Run with a rendering driver so the viewport has real pixels:
##
##   godot --path . --rendering-driver opengl3 -s tests/manual/visitor_shelf_preview.gd
##
## The image lands in `tmp_preview/visitor_shelf.png` (git-ignored). It is a
## manual check for the visitor plates, not part of the test suite. Without a
## display it runs the layout headless and skips the capture.
##
## Game classes are resolved through load() at runtime: referenced classes are
## compiled when this script is parsed, and the autoload singletons the game
## scripts use are only registered once the main loop starts.

const OUT := "res://tmp_preview/visitor_shelf.png"

const NAMES := ["Aaron Sterling", "Priya Natarajan", "Marcus Whitfield",
	"Elena Vasquez", "Tom Okafor", "Grace Lindqvist", "Henry Castellano"]


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var golfer_script: GDScript = load("res://scripts/entities/golfer.gd")
	var portrait_script: GDScript = load("res://scripts/ui/components/visitor_portrait.gd")
	var toolbar_script: GDScript = load("res://scripts/ui/terrain_toolbar.gd")
	DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path("res://tmp_preview"))
	var main: Node = load("res://scenes/main/main.tscn").instantiate()
	root.add_child(main)
	await process_frame
	await process_frame

	main._on_main_menu_quick_start("Visitor shelf", 0, {"terrain_seed": 12345})
	await create_timer(1.0).timeout
	for i in range(20):
		await process_frame

	var golfers: Array = []
	for i in 5:
		golfers.append(golfer_script.new())

	var toolbar = main.terrain_toolbar
	toolbar.golfer_data_provider = func():
		var rows: Array = []
		for i in golfers.size():
			rows.append({
				"id": i + 1,
				"name": NAMES[i],
				"tier": (i % 3) + 1,
				"hole": i + 1,
				"strokes": 3 + i,
				"attitude": 0.7,
				"portrait": portrait_script.for_golfer(golfers[i]),
			})
		return rows
	toolbar.record_completed_round({"name": NAMES[5], "strokes": 71, "par": 72, "day": 3, "tier": 2,
		"portrait": portrait_script.for_golfer(golfers[0])})
	toolbar.record_completed_round({"name": NAMES[6], "strokes": 78, "par": 72, "day": 4, "tier": 3,
		"portrait": portrait_script.for_golfer(golfers[1])})
	toolbar.select_tab(toolbar_script.Tab.GOLFERS)

	for i in range(30):
		await process_frame
	var viewport := root.get_viewport()
	var image: Image = viewport.get_texture().get_image() if viewport else null
	if image:
		image.save_png(OUT)
		print("saved ", OUT)
	else:
		print("no viewport image (headless display)")
	quit()
