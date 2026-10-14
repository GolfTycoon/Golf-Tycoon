extends GameTest
## Rotation uses mirrored bitmap arrows rather than missing font glyphs;
## the compass state and scene connections stay intact.

## Node paths come out of the scene's state prefixed with the scene root.
const ROTATE_CONTROLS := "./UI/HUD/BottomBar/LeftControls/RotateViewControls"

func test_font_has_no_glyph_for_the_old_rotate_arrows() -> void:
	# U+27F2 / U+27F3 — the arrows the buttons used to be labelled with.
	assert_false(ThemeDB.fallback_font.has_char(0x27F2),
		"The ⟲ glyph is missing from the font, so the button must draw its arrow")
	assert_false(ThemeDB.fallback_font.has_char(0x27F3),
		"The ⟳ glyph is missing from the font, so the button must draw its arrow")

func test_pixel_arrows_are_mirrored_and_keep_their_direction() -> void:
	var ccw: Array = PixelCircleButton.ICONS["rotate_ccw"]
	var cw: Array = PixelCircleButton.ICONS["rotate_cw"]
	assert_eq(ccw.size(), cw.size())
	for row in ccw.size():
		assert_eq(ccw[row].reverse(), cw[row], "Each arrow mirrors the other")
	var button := RotateViewButton.new()
	add_child_autofree(button)
	assert_eq(button.glyph, "rotate_ccw")
	button.clockwise = true
	assert_eq(button.glyph, "rotate_cw")

func test_buttons_are_drawn_not_typed() -> void:
	var ccw_button := RotateViewButton.new()
	add_child_autofree(ccw_button)
	assert_eq(ccw_button.text, "", "The sweep is the label: no glyph is typed on the face")
	assert_false(ccw_button.clockwise, "The Q button sweeps counter-clockwise")
	# The drawn arrow keeps the footprint the text buttons had.
	assert_eq(ccw_button.custom_minimum_size, Vector2(32, 32))

	var cw_button := RotateViewButton.new()
	cw_button.clockwise = true
	add_child_autofree(cw_button)
	assert_true(cw_button.clockwise, "The Shift+Q button sweeps clockwise")
	assert_eq(cw_button.text, "")

func test_needle_points_the_way_the_course_faces() -> void:
	assert_true(CompassNeedle.needle_direction(0).is_equal_approx(Vector2.UP), "N points up")
	assert_true(CompassNeedle.needle_direction(1).is_equal_approx(Vector2.RIGHT), "E points right")
	assert_true(CompassNeedle.needle_direction(2).is_equal_approx(Vector2.DOWN), "S points down")
	assert_true(CompassNeedle.needle_direction(3).is_equal_approx(Vector2.LEFT), "W points left")

func test_needle_turns_a_quarter_turn_per_rotation() -> void:
	var needle := CompassNeedle.new()
	add_child_autofree(needle)
	assert_eq(needle.orientation, 0, "A fresh needle faces north")
	needle.orientation = 3
	assert_eq(needle.orientation, 3, "West")
	# A fourth rotation comes full circle, and rotating back from north is west.
	needle.orientation = 4
	assert_eq(needle.orientation, 0, "Four quarter turns come back to north")
	needle.orientation = -1
	assert_eq(needle.orientation, 3, "Turning back from north faces west")

func test_scene_brackets_the_compass_with_the_two_rotate_arrows() -> void:
	var scene: PackedScene = load("res://scenes/main/main.tscn")
	var state := scene.get_state()
	var children := _child_names(state, ROTATE_CONTROLS)
	assert_eq(children, ["RotateCCWBtn", "OrientationNeedle", "OrientationLabel", "RotateCWBtn"],
		"The needle and its letter stand between the two Rotate arrows")

	var ccw := _node_index(state, ROTATE_CONTROLS + "/RotateCCWBtn")
	var cw := _node_index(state, ROTATE_CONTROLS + "/RotateCWBtn")
	var needle := _node_index(state, ROTATE_CONTROLS + "/OrientationNeedle")
	assert_ne(ccw, -1, "The counter-clockwise button is in the scene")
	assert_ne(cw, -1, "The clockwise button is in the scene")
	assert_ne(needle, -1, "The compass needle is in the scene")

	assert_eq(_script_name(state, ccw), "RotateViewButton")
	assert_eq(_script_name(state, cw), "RotateViewButton")
	assert_eq(_script_name(state, needle), "CompassNeedle")

	# Only the clockwise button sweeps clockwise.
	assert_eq(_property(state, cw, "clockwise"), true)
	assert_null(_property(state, ccw, "clockwise"))
	# Neither button falls back to the glyphs the font cannot print.
	for button in [ccw, cw]:
		var text = _property(state, button, "text")
		assert_true(text == null or text == "", "No glyph text is left on the Rotate buttons")

func _node_index(state: SceneState, path: String) -> int:
	for i in state.get_node_count():
		if str(state.get_node_path(i)) == path:
			return i
	return -1

## The children of `parent`, in the order the scene lists them.
func _child_names(state: SceneState, parent: String) -> Array[String]:
	var names: Array[String] = []
	for i in state.get_node_count():
		var path := str(state.get_node_path(i))
		if path.begins_with(parent + "/") and path.get_slice_count("/") == parent.get_slice_count("/") + 1:
			names.append(state.get_node_name(i))
	return names

func _property(state: SceneState, node_index: int, property_name: String) -> Variant:
	for p in state.get_node_property_count(node_index):
		if state.get_node_property_name(node_index, p) == property_name:
			return state.get_node_property_value(node_index, p)
	return null

func _script_name(state: SceneState, node_index: int) -> String:
	var script: Script = _property(state, node_index, "script")
	return str(script.get_global_name()) if script else ""
