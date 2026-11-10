extends MainSceneTest
## Feed notices are a passive layer.
##
## A feed entry raises a toast (and the autosave badge and the round summary are
## notices of the same kind). They hang over the course and the gameplay HUD,
## but a screen owns the player's attention while it is open: the Save Course and
## Save/Load desks in particular must never have a notice floating on top of
## them. The notices live in their own CanvasLayer under the UI layer, so every
## screen - whichever order it was added in - covers them.

const NOTICES_LAYER := "Notices"


## The CanvasLayer a control draws in, 0 when it sits in the plain world canvas.
## Godot draws every higher layer over every lower one, so this is the whole
## answer to "which of these two is on top?".
static func _canvas_layer_of(node: Node) -> int:
	while node != null:
		if node is CanvasLayer:
			return (node as CanvasLayer).layer
		node = node.get_parent()
	return 0


func before_all() -> void:
	await super()
	await new_game()


func after_each() -> void:
	main._close_save_screens()
	var archive := main.get_node_or_null("UI/HUD/SaveLoadPanel")
	if archive != null:
		archive.queue_free()
	if is_instance_valid(main.event_feed_panel) and main.event_feed_panel.visible:
		main._toggle_event_feed()
	await super()


# ---------------------------------------------------------------------------
# The band
# ---------------------------------------------------------------------------

func test_notices_draw_between_the_course_and_the_ui() -> void:
	var notices := main.get_node_or_null(NOTICES_LAYER) as CanvasLayer
	assert_not_null(notices, "the scene has a notice band")
	if notices == null:
		return
	var ui := main.get_node("UI") as CanvasLayer
	assert_gt(notices.layer, 0, "notices paint over the course")
	assert_gt(ui.layer, notices.layer, "the HUD and its screens paint over the notices")
	assert_not_null(notices.get_node_or_null("NotificationToast"),
		"the feed's toasts live in the notice band")
	assert_not_null(notices.get_node_or_null("AutosaveIndicator"),
		"the autosave badge lives in the notice band")
	assert_not_null(notices.get_node_or_null("RoundSummaryPopup"),
		"the round summary lives in the notice band")
	assert_null(main.get_node("UI").get_node_or_null("NotificationToast"),
		"no notice is left directly on the UI layer, above every screen")


func test_the_notice_band_follows_the_gameplay_hud() -> void:
	var notices := main.get_node(NOTICES_LAYER) as CanvasLayer
	main._set_gameplay_ui_visible(false)
	assert_false(notices.visible, "a title or map screen takes the notices with the HUD")
	main._set_gameplay_ui_visible(true)
	assert_true(notices.visible, "returning to the course brings the notice band back")


# ---------------------------------------------------------------------------
# Screens cover the notices
# ---------------------------------------------------------------------------

func test_a_feed_toast_never_covers_a_save_course_screen() -> void:
	main._open_save_screen(true)
	await process_frames(2)
	var screen := main.get_node_or_null("UI/HUD/SaveCourseScreen") as Control
	assert_not_null(screen, "the Save Course screen is open")
	if screen == null:
		return

	# Raise a notice while the screen is up, the way a feed entry can.
	EventBus.notify("Integration notice over a screen", "warning")
	await process_frames(2)
	var toast := main.get_node("Notices/NotificationToast") as NotificationToast
	assert_gt(toast._active_toasts.size(), 0, "the notice really is on screen")
	var panel := toast._active_toasts[0] as Control
	assert_true(panel.is_visible_in_tree(), "the toast itself is still showing")
	assert_true(rect_within(panel.get_global_rect(), Rect2(Vector2.ZERO, Screen.window_size)),
		"the toast still sits over the course where it belongs")
	assert_lt(_canvas_layer_of(panel), _canvas_layer_of(screen),
		"the Save Course screen draws over the toast, not the other way round")


func test_a_feed_toast_never_covers_the_save_load_desk() -> void:
	main._show_save_load_panel(true, SaveLoadPanel.ScreenMode.SAVE)
	await process_frames(2)
	var archive := main.get_node_or_null("UI/HUD/SaveLoadPanel") as SaveLoadPanel
	assert_not_null(archive, "the Save/Load desk is open")
	if archive == null:
		return

	EventBus.notify("Integration notice over the archive", "warning")
	await process_frames(2)
	var toast := main.get_node("Notices/NotificationToast") as NotificationToast
	assert_gt(toast._active_toasts.size(), 0, "the notice really is on screen")
	var panel := toast._active_toasts[0] as Control
	assert_lt(_canvas_layer_of(panel), _canvas_layer_of(archive),
		"the Save/Load desk draws over the toast")


func test_the_open_feed_panel_stays_behind_a_screen() -> void:
	main._toggle_event_feed()
	await process_frames(2)
	var feed := main.get_node("UI/HUD/EventFeedPanel") as EventFeedPanel
	assert_true(feed.visible, "the feed is open")
	main._open_save_screen(true)
	await process_frames(2)
	var screen := main.get_node_or_null("UI/HUD/SaveCourseScreen") as Control
	assert_not_null(screen, "the Save Course screen is open")
	if screen == null:
		return
	assert_gt(screen.get_index(), feed.get_index(),
		"the screen is drawn over the open feed, which stays where it was")
