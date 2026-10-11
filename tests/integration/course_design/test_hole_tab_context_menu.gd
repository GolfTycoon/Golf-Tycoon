extends MainSceneTest
## The Course Holes tab on the Quick Start course: one button per hole, three to
## a column, and a button opens that hole's context menu — the menu the course's
## tee, green and flag open — instead of the statistics screen. The menu still
## reaches the open/closed state, the par and the statistics, and Delete Hole
## asks before it deletes.

var hole_grid: GridContainer


func before_all() -> void:
	await super()
	await quick_start("Hole tab")
	hole_grid = main.hole_grid


## The context menu's button labelled `label`, or null.
func _menu_button(menu: Node, label: String) -> Button:
	for child in menu.find_children("*", "Button", true, false):
		if (child as Button).text == label:
			return child
	return null


## Hole numbers in the order the tab's slots hold them.
func _slot_holes() -> Array:
	var holes := []
	for slot in hole_grid.get_child_count():
		holes.append(int(hole_grid.get_child(slot).get_meta("hole_number")))
	return holes


func test_one_button_per_hole_three_to_a_column() -> void:
	var hole_count := GameManager.current_course.holes.size()
	assert_eq(hole_count, 9, "Quick Start builds nine holes")
	assert_eq(hole_grid.get_child_count(), hole_count, "One button per hole")
	assert_eq(hole_grid.find_children("*", "Button", true, false).size(), hole_count,
		"No Open/Close or Delete button sits beside a hole button")
	assert_eq(hole_grid.columns, 3, "Nine holes fill three columns of three")
	assert_eq(_slot_holes(), [1, 4, 7, 2, 5, 8, 3, 6, 9], "The holes read down the columns")


func test_a_hole_button_opens_the_holes_context_menu() -> void:
	main._on_hole_button_pressed(2)
	await process_frames(3)
	assert_not_null(main.get_node("UI").get_node_or_null("HoleContextMenu"),
		"A hole button opens the hole's context menu")
	assert_not_null(main._hole_context_menu, "The menu is open")
	if main._hole_context_menu:
		assert_eq(main._hole_context_menu.hole_data.hole_number, 2, "The menu is for the hole that was clicked")
	assert_false(main.hole_stats_panel.visible, "The statistics screen stays closed")

	# The menu owns the open/closed state the button reflects...
	main._on_context_toggle_hole(2)
	await process_frames(3)
	assert_false(GameManager.current_course.holes[1].is_open, "The menu closed hole 2")
	var hole_two: Button = hole_grid.get_node("HoleBtn2")
	assert_lt(hole_two.modulate.r, 1.0, "The closed hole's button dims")
	assert_string_contains(hole_two.tooltip_text, "Closed", "The closed hole says so in its tooltip")

	# ...and the par, which the button's label reads back.
	main._on_context_par_override(2, 5)
	await process_frames(3)
	assert_string_contains(hole_two.text, "P5", "The button reads back the new par")
	main._on_context_view_stats(2)
	await process_frames(3)
	assert_true(main.hole_stats_panel.visible, "The menu still reaches the statistics screen")
	main._on_hole_stats_panel_closed()
	main._close_hole_context_menu()
	# Let the closed menu leave the tree, the way a click would.
	await process_frames(3)


func test_delete_hole_asks_first_and_the_columns_close_the_gap() -> void:
	var hole_count := GameManager.current_course.holes.size()
	var first_tee: Vector2i = GameManager.current_course.holes[0].tee_position
	var first_green: Vector2i = GameManager.current_course.holes[0].green_position
	main._on_hole_button_pressed(1)
	await process_frames(3)
	var menu = main.get_node("UI").get_node_or_null("HoleContextMenu")
	assert_not_null(menu, "The hole button opened its menu")
	var delete_button := _menu_button(menu, "Delete Hole") if menu else null
	assert_not_null(delete_button, "The menu offers Delete Hole")
	if delete_button:
		delete_button.pressed.emit()
		await process_frames(3)

	var hud = main.get_node("UI/HUD")
	var question = hud.get_node_or_null("DeleteHoleConfirmDialog")
	assert_not_null(question, "Delete Hole asks before it deletes")
	assert_null(main._hole_context_menu, "The menu closes behind the question")
	if question:
		question._on_cancel()
		await process_frames(3)
	assert_eq(GameManager.current_course.holes.size(), hole_count, "Cancelling keeps every hole")
	assert_null(hud.get_node_or_null("DeleteHoleConfirmDialog"), "The question goes away")
	assert_eq(hole_grid.get_child_count(), hole_count, "Every hole keeps its button")

	main._on_context_delete_hole(1)
	await process_frames(3)
	question = hud.get_node_or_null("DeleteHoleConfirmDialog")
	assert_not_null(question, "Delete Hole asks again on the second try")
	if question:
		question._on_confirm()
		await process_frames(3)
	assert_eq(GameManager.current_course.holes.size(), hole_count - 1, "Confirming deletes the hole")
	# What the question promised: the tiles stay painted for the next hole.
	assert_eq(main.terrain_grid.get_tile(first_tee), TerrainTypes.Type.TEE_BOX,
		"The deleted hole's tee box stays painted")
	assert_eq(main.terrain_grid.get_tile(first_green), TerrainTypes.Type.GREEN,
		"The deleted hole's green stays painted")

	# A hole that goes leaves no gap in the columns.
	assert_eq(hole_grid.get_child_count(), 8, "Eight holes are left")
	assert_eq(hole_grid.columns, 3, "Eight holes fill two columns of three and start a third")
	assert_eq(_slot_holes(), [1, 4, 7, 2, 5, 8, 3, 6], "The remaining holes are renumbered down the columns")
