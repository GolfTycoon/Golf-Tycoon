extends GameTest
## The shot-type row: one button per shot type, mutually exclusive, following
## `Golfer.shape_allowed()` so the lit button is always the shot that will be
## hit.

var bar: ShotTypeBar
var reported: Array[int] = []

func before_each() -> void:
	super()
	bar = ShotTypeBar.new()
	add_child_autofree(bar)
	reported.clear()
	bar.shape_selected.connect(func(shape: int): reported.append(shape))

func _press(shape: int) -> void:
	var button := bar.shot_button(shape)
	button.button_pressed = true
	button.pressed.emit()

func test_one_button_per_shot_type_in_shape_order() -> void:
	var labels: Array[String] = []
	for shape in bar.shot_count():
		labels.append(bar.shot_button(shape).text)
	assert_eq(labels, ["Straight", "Fade", "Draw", "Backspin", "Punch"])
	for shape in bar.shot_count():
		var button := bar.shot_button(shape)
		assert_true(button.toggle_mode, "Shot buttons hold their selection")
		assert_true(button.button_group != null, "Exactly one shot can be selected")
		assert_eq(int(button.get_meta("shot_type")), shape)
		assert_false(button.tooltip_text.is_empty(), "Each shot explains itself on hover")

func test_pressing_a_shot_lights_it_and_reports_it_once() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	_press(2)
	assert_eq(reported, [2], "One press reports one shot")
	assert_eq(bar.selected_shape(), 2)
	assert_true(bar.shot_button(2).button_pressed)
	assert_false(bar.shot_button(0).button_pressed, "The previous shot releases")

func test_only_one_shot_is_ever_lit() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.TEE_BOX)
	_press(1)
	_press(3)
	_press(4)
	assert_eq(bar.selected_shape(), 4)
	var lit := 0
	for shape in bar.shot_count():
		if bar.shot_button(shape).button_pressed:
			lit += 1
	assert_eq(lit, 1, "The row never lights two shots")

## Straight and low punch play from any off-green lie; the bend shots need a tee
## or fairway — `Golfer.shape_allowed()`, the execution guard's own rule.
func test_the_lie_greys_out_the_shots_it_forbids() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.ROUGH)
	assert_false(bar.shot_button(0).disabled, "Straight is always available")
	assert_false(bar.shot_button(4).disabled, "Low punch is always available")
	for shape in [1, 2, 3]:
		assert_true(bar.shot_button(shape).disabled, "Bend shots need tee or fairway")
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	for shape in bar.shot_count():
		assert_false(bar.shot_button(shape).disabled, "Every shot is available from fairway")

func test_an_illegal_selection_falls_back_to_straight() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	_press(2)
	assert_eq(bar.selected_shape(), 2)
	var fell_back := bar.update_for_lie(TerrainTypes.Type.BUNKER)
	assert_true(fell_back, "The caller is told to mirror the fallback")
	assert_eq(bar.selected_shape(), 0)
	assert_true(bar.shot_button(0).button_pressed, "Straight lights up in place")
	assert_eq(reported.size(), 1, "The fallback is not a new press")

func test_the_row_is_dead_while_the_owner_waits() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	bar.set_ready(false)
	for shape in bar.shot_count():
		assert_true(bar.shot_button(shape).disabled, "Every shot greys out between turns")
	_press(1)
	assert_eq(reported, [], "A dead row reports nothing")
	assert_eq(bar.selected_shape(), 0, "A dead row keeps the lit shot")

## A dead row greys out, but the loaded shot keeps its ring so the owner can
## still see what is selected while they wait their turn.
func test_the_loaded_shot_stays_readable_on_a_dead_row() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	bar.select_shape(2)
	bar.set_ready(false)
	assert_ne(bar.shot_button(2).get_theme_stylebox("disabled"),
		bar.shot_button(0).get_theme_stylebox("disabled"),
		"The lit shot is ringed apart from the other greyed shots")
	assert_eq(bar.shot_button(0).get_theme_stylebox("disabled"),
		bar.shot_button(4).get_theme_stylebox("disabled"),
		"Every unlit shot shares the same greyed face")

func test_select_shape_mirrors_the_golfer_without_reporting() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	bar.select_shape(3)
	assert_eq(bar.selected_shape(), 3)
	assert_true(bar.shot_button(3).button_pressed)
	assert_eq(reported, [], "Mirroring the golfer is not a press")
	bar.select_shape(99)
	assert_eq(bar.selected_shape(), 0, "Out-of-range shapes fall back to straight")

## Every button carries its own picture of the shot it names — the arc it flies
## and the roll that follows — in the slot above the label.
func test_each_shot_button_carries_a_picture_of_its_own_shot() -> void:
	await process_frames(1)
	for shape in bar.shot_count():
		var button := bar.shot_button(shape)
		var diagram := bar.shot_diagram(shape)
		assert_true(diagram is ShotShapeDiagram, "shot %d has a legend" % shape)
		assert_eq(diagram.get_parent(), button, "the legend rides on its own button")
		assert_eq(diagram.shape, shape, "and pictures the shot the button names")
		assert_eq(diagram.mouse_filter, Control.MOUSE_FILTER_IGNORE,
			"the legend never takes the clicks and hovers its button answers")
		# The legend sits in the slot the styleboxes reserve above the label, so
		# picture and name never share a line.
		assert_almost_eq(diagram.position.y, ShotTypeBar.DIAGRAM_TOP, 0.01,
			"shot %d's legend sits in the top slot" % shape)
		assert_almost_eq(diagram.size.y, ShotShapeDiagram.DIAGRAM_HEIGHT, 0.01)
		assert_lte(diagram.position.y + diagram.size.y, ShotTypeBar.text_top_margin(),
			"the legend ends where the label's slot begins")
		assert_true(Rect2(Vector2.ZERO, button.size).encloses(Rect2(diagram.position, diagram.size)),
			"the whole legend is inside its button")
		assert_almost_eq(diagram.position.x + diagram.size.x * 0.5, button.size.x * 0.5, 0.5,
			"centred over the label")

## A greyed button keeps its picture but loses its colour, so the row still
## teaches the shapes while it waits for a lie or a turn.
func test_the_pictures_grey_out_with_their_buttons() -> void:
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.ROUGH)
	for shape in [0, 4]:
		assert_true(bar.shot_diagram(shape).enabled, "shape %d keeps its colour" % shape)
	for shape in [1, 2, 3]:
		assert_false(bar.shot_diagram(shape).enabled,
			"a shot this lie forbids is drawn in the muted grey")
	bar.set_ready(false)
	for shape in bar.shot_count():
		assert_false(bar.shot_diagram(shape).enabled, "a dead row greys every picture out")
	bar.set_ready(true)
	bar.update_for_lie(TerrainTypes.Type.FAIRWAY)
	for shape in bar.shot_count():
		assert_true(bar.shot_diagram(shape).enabled, "the fairway lights them all again")

## The row's height is the legend's slot over the label and nothing more, so the
## Play Course page keeps room for both.
func test_the_row_is_exactly_the_legend_slot_over_the_label() -> void:
	await process_frames(1)
	assert_almost_eq(bar.get_combined_minimum_size().y, float(ShotTypeBar.BUTTON_HEIGHT), 0.01)
	for shape in bar.shot_count():
		var button := bar.shot_button(shape)
		var top: float = button.get_theme_stylebox("normal").content_margin_top
		assert_almost_eq(top, ShotTypeBar.text_top_margin(), 0.01,
			"every face reserves the same slot, or the label jumps between states")
		assert_almost_eq(button.get_theme_stylebox("disabled").content_margin_top, top, 0.01)
		assert_almost_eq(button.get_theme_stylebox("pressed").content_margin_top, top, 0.01)
