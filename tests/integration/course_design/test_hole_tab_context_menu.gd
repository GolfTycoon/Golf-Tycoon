extends MainSceneTest
## The Course Holes tab on the Quick Start course: one row per hole, three to
## a column, and clicking a hole button opens that hole's management actions and
## statistics right on the Holes tab — in place of the hole register, the way
## clicking a visitor opens their profile on Visiting Golfers — instead of a
## separate popup menu or statistics modal.

var hole_grid: GridContainer


func before_all() -> void:
	await super()
	await quick_start("Hole tab")
	hole_grid = main.hole_grid


## The container's button labelled `label`, or null.
func _detail_button(container: Node, label: String) -> Button:
	for child in container.find_children("*", "Button", true, false):
		if (child as Button).text == label:
			return child
	return null


## All label text inside `container`.
func _detail_text(container: Node) -> String:
	var text := ""
	for child in container.find_children("*", "Label", true, false):
		text += (child as Label).text + "\n"
	return text


## Hole numbers in the order the tab's slots hold them.
func _slot_holes() -> Array:
	var holes := []
	for slot in hole_grid.get_child_count():
		holes.append(int(hole_grid.get_child(slot).get_meta("hole_number")))
	return holes


func test_one_button_per_hole_three_to_a_column() -> void:
	var hole_count := GameManager.current_course.holes.size()
	assert_eq(hole_count, 9, "Quick Start builds nine holes")
	assert_eq(hole_grid.get_child_count(), hole_count, "One row per hole")
	assert_eq(hole_grid.find_children("*", "Button", true, false).size(), hole_count * 2,
		"Each hole has a detail button and a Locate button")
	assert_eq(hole_grid.columns, 3, "Nine holes fill three columns of three")
	assert_eq(_slot_holes(), [1, 4, 7, 2, 5, 8, 3, 6, 9], "The holes read down the columns")


func test_locate_buttons_focus_each_hole_without_opening_details() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	toolbar.close_hole_detail()
	toolbar.select_tab(TerrainToolbar.Tab.HOLES)
	for hole in GameManager.current_course.holes:
		var hole_button: Button = main._find_hole_button(hole.hole_number)
		var locate := hole_button.get_parent().get_node("LocateHoleButton%d" % hole.hole_number) as Button
		assert_eq(locate.text, "Locate", "Locate sits beside each hole button")
		main.camera.focus_on(Vector2(-10000, -10000), true)
		locate.pressed.emit()
		var center: Vector2 = (main.terrain_grid.grid_to_screen_center(hole.tee_position) 			+ main.terrain_grid.grid_to_screen_center(hole.green_position)) / 2
		assert_eq(main.camera._target_position, center, "Locate focuses the tee-to-green midpoint")
		assert_true(toolbar._hole_register.visible, "Locate leaves the register open")
		assert_eq(toolbar._selected_hole, 0, "Locate does not select a detail view")


func test_a_hole_button_opens_the_hole_detail_on_the_holes_tab() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	main._on_hole_button_pressed(2)
	await process_frames(3)
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.HOLES, "The Holes tab is shown")
	assert_eq(toolbar._selected_hole, 2, "Hole 2 is selected on the Holes tab")
	assert_false(toolbar._hole_register.visible, "The hole register steps aside")
	assert_true(toolbar._hole_detail.visible, "and the hole detail view takes the tab")
	assert_null(main.get_node("UI").get_node_or_null("HoleContextMenu"),
		"A hole button no longer opens a separate floating context menu")
	assert_false(main.hole_stats_panel.visible, "The separate statistics modal stays closed")

	var text := _detail_text(toolbar._hole_detail)
	assert_string_contains(text, "Hole 2 — Par", "The detail view names the hole and its par")
	assert_string_contains(text, "Hole Information", "The detail view includes Hole Information")
	assert_string_contains(text, "Scoring Statistics", "The detail view includes Scoring Statistics inline")

	# The Holes tab detail view owns the open/closed state the button reflects...
	var toggle_btn := _detail_button(toolbar._hole_detail, "Close Hole")
	assert_not_null(toggle_btn, "The detail view offers Close Hole")
	if toggle_btn:
		toggle_btn.pressed.emit()
		await process_frames(3)
	assert_false(GameManager.current_course.holes[1].is_open, "The detail view closed hole 2")
	var hole_two: Button = main._find_hole_button(2)
	assert_lt(hole_two.modulate.r, 1.0, "The closed hole's button dims")
	assert_string_contains(hole_two.tooltip_text, "Closed", "The closed hole says so in its tooltip")
	assert_not_null(_detail_button(toolbar._hole_detail, "Open Hole"),
		"The detail view flips its toggle to Open Hole")

	# ...and the par, which both the detail view and the button's readout read back.
	main._on_context_par_override(2, 5)
	await process_frames(3)
	assert_string_contains((hole_two as HoleCardButton).readout_text(), "P5",
		"The button reads back the new par")
	assert_string_contains(_detail_text(toolbar._hole_detail), "Hole 2 — Par 5",
		"The detail view reads back the new par")

	# Returning via the back button restores the hole register.
	var back_btn := _detail_button(toolbar._hole_detail, "< Holes")
	assert_not_null(back_btn, "The detail view has a back button to return to the holes list")
	if back_btn:
		back_btn.pressed.emit()
		await process_frames(3)
	assert_true(toolbar._hole_register.visible, "The hole register is back up")
	assert_false(toolbar._hole_detail.visible, "and the hole detail view is hidden")


func test_delete_hole_asks_first_and_the_columns_close_the_gap() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	var hole_count := GameManager.current_course.holes.size()
	var first_tee: Vector2i = GameManager.current_course.holes[0].tee_position
	var first_green: Vector2i = GameManager.current_course.holes[0].green_position
	main._on_hole_button_pressed(1)
	await process_frames(3)
	assert_true(toolbar._hole_detail.visible, "The hole button opened its detail view on the Holes tab")
	var delete_button := _detail_button(toolbar._hole_detail, "Delete Hole")
	assert_not_null(delete_button, "The detail view offers Delete Hole")
	if delete_button:
		delete_button.pressed.emit()
		await process_frames(3)

	var hud = main.get_node("UI/HUD")
	var question = hud.get_node_or_null("DeleteHoleConfirmDialog")
	assert_not_null(question, "Delete Hole asks before it deletes")
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
	# Deleting the hole returns the Holes tab to the register.
	assert_true(toolbar._hole_register.visible, "Deleting the open hole returns to the hole register")
	assert_false(toolbar._hole_detail.visible, "and closes the deleted hole's detail view")
	# What the question promised: the tiles stay painted for the next hole.
	assert_eq(main.terrain_grid.get_tile(first_tee), TerrainTypes.Type.TEE_BOX,
		"The deleted hole's tee box stays painted")
	assert_eq(main.terrain_grid.get_tile(first_green), TerrainTypes.Type.GREEN,
		"The deleted hole's green stays painted")

	# A hole that goes leaves no gap in the columns.
	assert_eq(hole_grid.get_child_count(), 8, "Eight holes are left")
	assert_eq(hole_grid.columns, 3, "Eight holes fill two columns of three and start a third")
	assert_eq(_slot_holes(), [1, 4, 7, 2, 5, 8, 3, 6], "The remaining holes are renumbered down the columns")
