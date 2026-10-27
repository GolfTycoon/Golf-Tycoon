extends GameTest
## A placement ghost is a preview of a building that does not exist yet. Once
## the building is placed (or the placement is cancelled), its ghost must go
## away immediately: it is a separate CanvasItem child, not a stroke this node
## paints, so a missed redraw would leave a translucent second building on the
## course. These tests cover the signal-driven cleanup and the frame-driven
## fallback for scripted/modded flows that change the mode without a signal.

var manager: PlacementManager
var preview: PlacementPreview


func before_each() -> void:
	super()
	manager = PlacementManager.new()
	preview = PlacementPreview.new()
	add_child_autofree(preview)
	# Cleanup must not depend on the next idle frame or redraw.
	preview.set_process(false)
	preview.set_placement_manager(manager)
	preview.terrain_grid = null


## Stand a ghost on a tile the way _draw() does while a facility is selected.
func _show_ghost() -> void:
	preview.current_preview_positions = [Vector2i(4, 4)]
	preview.current_preview_valid = true
	preview._draw_building_ghost_shape(Vector2i(4, 4), "pro_shop", Vector2i(2, 2),
			Color(0.3, 0.9, 0.3, 0.6))
	assert_true(preview._building_ghost.visible, "The hover ghost is showing")


func test_cancelling_a_placement_puts_the_ghost_away_without_a_redraw() -> void:
	manager.start_building_placement("pro_shop", {"size": [2, 2]})
	_show_ghost()

	# Every placement ends through cancel_placement(), which emits this signal.
	manager.cancel_placement()

	assert_false(preview._building_ghost.visible,
			"The ghost is hidden the moment the placement ends")
	assert_true(preview.current_preview_positions.is_empty(),
			"The hovered footprint is forgotten too")
	assert_false(preview.current_preview_valid, "and its validity colour is reset")


func test_a_long_frame_cannot_strand_a_ghost_during_the_fade_out() -> void:
	manager.start_building_placement("pro_shop", {"size": [2, 2]})
	_show_ghost()
	preview._current_alpha = 1.0
	# A scripted placement can drop the mode directly, without the signal.
	manager.placement_mode = PlacementManager.PlacementMode.NONE
	# _real_delta() caps at 0.1s, and lerp(alpha, 0, 0.1 * 10) is exactly zero:
	# the old code skipped the only redraw that hid the ghost.
	preview._last_process_usec = Time.get_ticks_usec() - 500000
	preview._process(0.5)

	assert_lt(preview._current_alpha, 0.01, "The fade-out finished in one frame")
	assert_false(preview._building_ghost.visible,
			"The ghost is still hidden after the long frame")
	assert_true(preview.current_preview_positions.is_empty(),
			"and there is no footprint left to draw")
	await process_frames(3)
	assert_false(preview._building_ghost.visible, "It does not reappear later")


func test_setting_a_carried_building_down_puts_its_ghost_away() -> void:
	var clubhouse: Building = autofree(Building.new())
	preview.set_building_move_target(clubhouse)
	_show_ghost()

	preview.set_building_move_target(null)

	assert_false(preview._building_ghost.visible,
			"The move ghost goes away when the building is set down")
	assert_true(preview.current_preview_positions.is_empty(),
			"and the move footprint is cleared")


func test_the_next_placement_can_show_a_ghost_again() -> void:
	manager.start_building_placement("pro_shop", {"size": [2, 2]})
	_show_ghost()
	manager.cancel_placement()

	manager.start_building_placement("snack_bar", {"size": [2, 2]})
	preview.current_preview_positions = [Vector2i(6, 6)]
	preview._draw_entity_ghost(0.6)

	assert_true(preview._building_ghost.visible,
			"Clearing one ghost does not suppress the next hover")
	assert_eq(preview._building_ghost.kind, "snack_bar",
			"and the new ghost shows the newly selected facility")
