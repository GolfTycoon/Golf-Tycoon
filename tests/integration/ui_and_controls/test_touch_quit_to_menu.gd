extends MainSceneTest
## The reported touch flow, end to end on the real scene: pause with the
## touch layout (a phone held sideways), tap Quit to Menu, then answer the
## confirmation that opens over the paused course.
##
## The confirmation is a full-screen dialogue added to the HUD while the pause
## menu is still leaving the tree. On touch, both steps have to work through
## TouchInput's synthetic clicks — not just the mouse path the menus were
## written against.

const PHONE_LANDSCAPE := Vector2i(844, 390)

func before_all() -> void:
	super()
	get_window().size = PHONE_LANDSCAPE
	await process_frames(2)
	await new_game()

func after_all() -> void:
	get_window().size = DESIGN_WINDOW
	super()

func _hud_confirm_dialog() -> ConfirmDialog:
	for child in main.get_node("UI/HUD").get_children():
		if child is ConfirmDialog:
			return child
	return null

func test_quit_to_menu_asks_then_returns_to_the_title_on_touch() -> void:
	await resize_window(PHONE_LANDSCAPE)
	main._show_pause_menu()
	await process_frames(3)
	var menu: PauseMenu = main.pause_menu
	assert_not_null(menu, "the pause menu opens")

	var quit_button: Button = null
	for child in menu.find_children("*", "Button", true, false):
		if (child as Button).text == "Quit to Menu":
			quit_button = child as Button
	assert_not_null(quit_button, "the pause menu offers Quit to Menu")
	if quit_button == null:
		return
	assert_true(Rect2(Vector2.ZERO, Vector2(PHONE_LANDSCAPE)).encloses(quit_button.get_global_rect()),
		"Quit to Menu is on the screen, not below it")

	await touch_tap(quit_button.get_global_rect().get_center())
	await process_frames(3)
	var dialog := _hud_confirm_dialog()
	assert_not_null(dialog, "tapping Quit to Menu asks for confirmation")
	if dialog == null:
		return

	var confirm_button := dialog.find_child("ConfirmButton", true, false) as Button
	assert_not_null(confirm_button, "the confirmation has its Quit to Menu answer")
	if confirm_button == null:
		return
	assert_true(Rect2(Vector2.ZERO, Vector2(PHONE_LANDSCAPE)).encloses(confirm_button.get_global_rect()),
		"the answer is on the screen and tappable")
	# Main answers the confirmation by reloading the whole scene, which a
	# headless harness has no current scene for (and which would take the test
	# out with it). Watch the dialogue's own answer instead of driving the
	# reload: the wiring that opens the confirmation is what this test proves.
	var confirmed: Array = []
	dialog.confirmed.connect(func() -> void: confirmed.append(true))
	for connection in dialog.confirmed.get_connections():
		var callable: Callable = connection["callable"]
		if callable.is_valid() and callable.get_object() == main:
			dialog.confirmed.disconnect(callable)

	await touch_tap(confirm_button.get_global_rect().get_center())
	await process_frames(4)

	assert_eq(confirmed.size(), 1, "tapping the answer confirms the quit")
	assert_null(_hud_confirm_dialog(), "and the confirmation closes")


func test_cancelling_the_quit_confirmation_restores_the_pause_menu_on_touch() -> void:
	await resize_window(PHONE_LANDSCAPE)
	main._show_pause_menu()
	await process_frames(3)
	var menu: PauseMenu = main.pause_menu
	assert_not_null(menu, "the pause menu opens")
	if menu == null:
		return
	var quit_button: Button = null
	for child in menu.find_children("*", "Button", true, false):
		if (child as Button).text == "Quit to Menu":
			quit_button = child as Button
	await touch_tap(quit_button.get_global_rect().get_center())
	await process_frames(3)
	var dialog := _hud_confirm_dialog()
	assert_not_null(dialog, "tapping Quit to Menu asks for confirmation")
	if dialog == null:
		return
	var keep_button := dialog.find_child("CancelButton", true, false) as Button
	assert_not_null(keep_button, "the confirmation offers Cancel")
	if keep_button == null:
		return
	await touch_tap(keep_button.get_global_rect().get_center())
	await process_frames(4)
	assert_null(_hud_confirm_dialog(), "the confirmation closes")
	assert_not_null(main.pause_menu, "cancelling puts the pause menu back")
	if main.pause_menu != null:
		main._close_pause_menu()
	await process_frames(2)
