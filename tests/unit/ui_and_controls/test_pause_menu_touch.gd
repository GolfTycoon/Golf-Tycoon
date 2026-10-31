extends GameTest
## Touch use of the pause menu and the confirmation dialogue it opens.
##
## A phone held sideways is short: the pause menu used to be taller than the
## window, which pushed Quit to Menu and Quit to Desktop below the bottom edge
## where no finger (or focus ring) could reach them. The menu now fits, scrolls
## when it must, and the confirmation that follows keeps both of its answers on
## screen at every window size.

const PHONE_LANDSCAPE := Vector2i(844, 390)
const SMALL_LANDSCAPE := Vector2i(640, 360)
const PHONE_PORTRAIT := Vector2i(390, 844)

func _menu() -> PauseMenu:
	var menu := autofree(PauseMenu.new()) as PauseMenu
	add_child(menu)
	return menu

func _button_named(root: Control, text: String) -> Button:
	for child in root.find_children("*", "Button", true, false):
		if (child as Button).text == text:
			return child as Button
	return null

func _option_labels() -> Array:
	return ["Resume", "Save Game", "Load Game", "Settings", "Quit to Menu", "Quit to Desktop"]

func _inside_view(rect: Rect2, size: Vector2i) -> bool:
	return Rect2(Vector2.ZERO, Vector2(size)).encloses(rect)


func test_every_pause_option_is_on_screen_on_a_phone_held_sideways() -> void:
	await resize_window(PHONE_LANDSCAPE)
	var menu := _menu()
	await process_frames(4)
	assert_true(_inside_view(menu._panel.get_global_rect(), PHONE_LANDSCAPE),
		"the menu panel fits the window")
	for label in _option_labels():
		var button := _button_named(menu, label)
		assert_not_null(button, "%s exists" % label)
		if button != null:
			assert_true(_inside_view(button.get_global_rect(), PHONE_LANDSCAPE),
				"%s is on screen, so a finger can reach it" % label)


func test_a_short_pause_menu_scrolls_instead_of_losing_its_last_options() -> void:
	await resize_window(SMALL_LANDSCAPE)
	var menu := _menu()
	await process_frames(4)
	assert_true(_inside_view(menu._panel.get_global_rect(), SMALL_LANDSCAPE),
		"the panel itself never runs off the window")
	assert_ne(menu._scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"content taller than the panel becomes scrollable")

	var desktop_button := _button_named(menu, "Quit to Desktop")
	# A finger drag on the panel scrolls it (TouchInput's UI scroll gesture).
	var center := menu._panel.get_global_rect().get_center()
	var down := InputEventScreenTouch.new()
	down.index = 0
	down.pressed = true
	down.position = center
	get_viewport().push_input(down, true)
	for step in [40, 120, 240]:
		var drag := InputEventScreenDrag.new()
		drag.index = 0
		drag.position = center + Vector2(0, -step)
		get_viewport().push_input(drag, true)
	var up := InputEventScreenTouch.new()
	up.index = 0
	up.pressed = false
	up.position = center + Vector2(0, -240)
	get_viewport().push_input(up, true)
	await process_frames(3)
	assert_gt(menu._scroll.scroll_vertical, 0, "dragging the panel scrolls the menu")
	assert_true(_inside_view(desktop_button.get_global_rect(), SMALL_LANDSCAPE),
		"the last option is reachable once scrolled")


func test_quit_to_menu_answers_a_tap() -> void:
	await resize_window(PHONE_LANDSCAPE)
	var menu := _menu()
	await process_frames(4)
	var asked: Array = []
	menu.quit_to_menu_requested.connect(func() -> void: asked.append(true))
	var quit_button := _button_named(menu, "Quit to Menu")
	await touch_tap(quit_button.get_global_rect().get_center())
	assert_eq(asked.size(), 1, "a tap on Quit to Menu asks to quit")


func _dialog(message: String = "Unsaved progress will be lost.\nReturn to main menu?") -> ConfirmDialog:
	var dialog := autofree(ConfirmDialog.new(message, "Quit to Menu", "Cancel")) as ConfirmDialog
	add_child(dialog)
	return dialog


func test_confirmation_answers_are_tappable_at_every_window_shape() -> void:
	for size in [Vector2i(1600, 1000), Vector2i(1180, 820), PHONE_LANDSCAPE, PHONE_PORTRAIT]:
		await resize_window(size)
		var dialog := _dialog()
		await process_frames(3)
		assert_true(_inside_view(dialog._panel.get_global_rect(), size),
			"the confirmation panel fits %s" % size)
		var confirmed: Array = []
		dialog.confirmed.connect(func() -> void: confirmed.append(true))
		var confirm_button := dialog.find_child("ConfirmButton", true, false) as Button
		assert_not_null(confirm_button, "the confirmation has its answer at %s" % size)
		if confirm_button == null:
			continue
		assert_true(_inside_view(confirm_button.get_global_rect(), size),
			"the answer is on screen at %s" % size)
		await touch_tap(confirm_button.get_global_rect().get_center())
		assert_eq(confirmed.size(), 1, "a tap answers the confirmation at %s" % size)
		if is_instance_valid(dialog):
			dialog.free()
		await process_frames(2)


func test_a_long_question_scrolls_but_never_hides_the_answers() -> void:
	await resize_window(SMALL_LANDSCAPE)
	var long_question := "Every location you have not bought will get a new amount of ready land and a new asking price. Locations you own never change, whatever you decide here.\n\n"
	long_question = long_question.repeat(4)
	var dialog := _dialog(long_question)
	await process_frames(3)
	var keep := dialog.find_child("CancelButton", true, false) as Button
	var confirm_button := dialog.find_child("ConfirmButton", true, false) as Button
	assert_true(_inside_view(dialog._panel.get_global_rect(), SMALL_LANDSCAPE),
		"the panel stays inside a short window")
	assert_true(_inside_view(keep.get_global_rect(), SMALL_LANDSCAPE),
		"Keep stays on screen while the question scrolls")
	assert_true(_inside_view(confirm_button.get_global_rect(), SMALL_LANDSCAPE),
		"and so does the destructive answer")
	assert_ne(dialog._scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"the message area scrolls when it cannot fit")


func test_the_menu_reclaims_its_width_when_the_window_grows_back() -> void:
	await resize_window(PHONE_LANDSCAPE)
	var menu := _menu()
	await process_frames(4)
	var narrow_width := menu._panel.size.x
	await resize_window(Vector2i(1600, 1000))
	await process_frames(3)
	assert_gt(menu._panel.size.x, narrow_width,
		"a window that grows again gets the full-width menu back")
	assert_true(_inside_view(menu._panel.get_global_rect(), Vector2i(1600, 1000)))
	assert_eq(menu._scroll.vertical_scroll_mode, ScrollContainer.SCROLL_MODE_DISABLED,
		"and the menu no longer needs to scroll")
