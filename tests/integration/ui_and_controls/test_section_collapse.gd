extends MainSceneTest
## The Build, Manage and Golfers buttons in the bottom dock: pressing the button
## of the open section hides its shelf, and pressing it again (or choosing a tab)
## shows the shelf again.

func _press(section: int) -> void:
	main.left_controls.section_buttons[section].pressed.emit()

func test_section_buttons_hide_and_reveal_their_shelf() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	assert_true(toolbar.visible, "The Build shelf is open at the start")

	_press(TerrainToolbar.Section.BUILD)
	assert_false(toolbar.visible, "A press on the open Build section hides it")
	assert_false(main.left_controls.section_buttons[TerrainToolbar.Section.BUILD].active)

	_press(TerrainToolbar.Section.BUILD)
	assert_true(toolbar.visible, "Pressing Build again reopens it")
	assert_true(main.left_controls.section_buttons[TerrainToolbar.Section.BUILD].active)

	_press(TerrainToolbar.Section.GOLFERS)
	assert_eq(toolbar.current_section, TerrainToolbar.Section.GOLFERS)
	assert_true(toolbar.visible)
	_press(TerrainToolbar.Section.GOLFERS)
	assert_false(toolbar.visible, "Golfers hides too")

	_press(TerrainToolbar.Section.MANAGE)
	assert_true(toolbar.visible, "Manage opens while Golfers is hidden")
	assert_eq(toolbar.current_section, TerrainToolbar.Section.MANAGE)
	toolbar.collapse_section()
	toolbar.select_tab(TerrainToolbar.Tab.CLUB)
	assert_true(toolbar.visible, "Choosing a tab reopens the hidden section")

func test_hidden_section_shows_the_course_where_the_shelf_was() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	var backdrop := toolbar.get_node("ShelfFanBackdrop") as ShelfFanBackdrop
	assert_null(main.get_node_or_null("UI/HUD/BottomBarBG"),
		"there is no rectangular bar behind the curved shelf")
	assert_true(toolbar.visible and backdrop.visible, "the open shelf paints its own backdrop")
	toolbar.collapse_section()
	await process_frames(2)
	assert_false(toolbar.visible, "hiding the shelf also hides its child backdrop")
	toolbar.select_tab(TerrainToolbar.Tab.TERRAIN)
	await process_frames(2)
	assert_true(toolbar.visible and backdrop.visible, "reopening restores the curved backdrop")
