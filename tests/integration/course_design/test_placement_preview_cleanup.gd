extends MainSceneTest
## The Buildings tab previews a facility with a ghost that follows the cursor.
## Placing the facility must leave exactly one building on the course: the real
## one. The ghost is a separate CanvasItem, so it has to be put away when the
## placement ends rather than waiting for the overlay's next redraw.

const PLOT := Vector2i(48, 50)


func before_all() -> void:
	await super()
	await new_game("Placement ghost cleanup")


func test_placing_a_building_clears_its_hover_ghost() -> void:
	var preview: PlacementPreview = main.placement_preview
	main._on_building_type_selected_from_toolbar("pro_shop")
	await process_frames_until(func() -> bool: return preview._building_ghost.visible, 60)
	assert_true(preview._building_ghost.visible, "Hovering shows the building ghost")
	assert_false(preview.current_preview_positions.is_empty(), "and its footprint")

	# The real click path: place, then cancel the catalogue selection. No frame
	# is allowed to pass between the building appearing and the ghost leaving.
	main._place_building(PLOT, main.building_registry["pro_shop"]["cost"])

	assert_not_null(main.entity_layer.get_building_at(PLOT), "The building was placed")
	assert_false(preview._building_ghost.visible,
			"The ghost is gone as soon as the building is placed")
	assert_true(preview.current_preview_positions.is_empty(),
			"and the hovered footprint is forgotten")
	await process_frames(10)
	assert_false(preview._building_ghost.visible,
			"It stays gone while the pointer rests on the new building")


func test_a_long_frame_after_cancelling_does_not_bring_the_ghost_back() -> void:
	var preview: PlacementPreview = main.placement_preview
	main._on_building_type_selected_from_toolbar("snack_bar")
	await process_frames_until(func() -> bool: return preview._building_ghost.visible, 60)
	assert_true(preview._building_ghost.visible, "The next hover shows a ghost")

	main.placement_manager.cancel_placement()
	# Placing a building can cost a slow frame. The fade-out used to jump to
	# zero in that frame and skip the redraw that hid the ghost.
	preview._last_process_usec = Time.get_ticks_usec() - 500000
	preview._process(0.5)
	await process_frames(5)

	assert_false(preview._building_ghost.visible, "The ghost never returns")
	assert_lt(preview._current_alpha, 0.01, "The preview has finished fading out")
