extends MainSceneTest

func test_visitor_profile_and_locate_are_separate_actions() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	toolbar.golfer_data_provider = func(): return [{"id": 7, "name": "Ada Green", "tier": 1, "hole": 2, "strokes": 5}]
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	watch_signals(toolbar)
	var card: HBoxContainer = toolbar._visitor_shelf.get_child(0).get_child(0)
	card.get_child(0).pressed.emit()
	assert_eq(toolbar._selected_visitor, "Ada Green")
	assert_true(toolbar._visitor_detail.visible)
	assert_false(toolbar._visitor_register.visible)
	assert_signal_not_emitted(toolbar, "golfer_row_clicked")
	toolbar._visitor_detail.get_child(0).pressed.emit()
	assert_true(toolbar._visitor_register.visible)
	card = toolbar._visitor_shelf.get_child(0).get_child(0)
	card.get_child(1).pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "golfer_row_clicked", [7])
	assert_eq(toolbar._selected_visitor, "")

func test_history_is_clickable_deduplicated_and_not_capped_at_thirty() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	toolbar._visitor_archive.clear()
	toolbar._selected_visitor = ""
	toolbar.golfer_data_provider = func(): return []
	for i in 35:
		toolbar.record_completed_round({"name": "Visitor %d" % i, "strokes": 72, "par": 72, "day": 1})
	toolbar.record_completed_round({"name": "Visitor 0", "strokes": 70, "par": 72, "day": 2})
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	assert_eq(toolbar._visitor_archive.size(), 35)
	assert_eq(toolbar._visitor_archive["Visitor 0"].strokes, 70)
	var card: HBoxContainer = toolbar._visitor_shelf.get_child(0).get_child(0)
	assert_eq(card.get_child_count(), 1, "Past visitors have no locate button")
	card.get_child(0).pressed.emit()
	assert_eq(toolbar._selected_visitor, "Visitor 0")
	assert_true(toolbar._visitor_detail.visible)

func test_combined_list_places_active_golfers_before_history_and_keeps_skin() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	toolbar._visitor_archive.clear()
	toolbar._selected_visitor = ""
	var golfer := Golfer.new()
	var portrait := VisitorPortrait.for_golfer(golfer)
	assert_not_null(portrait, "Portrait comes from the golfer's actual skin frames")
	golfer.free()
	toolbar.golfer_data_provider = func(): return [{"id": 9, "name": "Current Visitor", "portrait": portrait}]
	toolbar.record_completed_round({"name": "Previous Visitor", "portrait": portrait})
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	var column: VBoxContainer = toolbar._visitor_shelf.get_child(0)
	assert_eq(column.get_child_count(), 2, "Active and past visitors share the same column")
	assert_true(column.get_child(0).get_child(0).text.begins_with("Current Visitor"))
	assert_true(column.get_child(1).get_child(0).text.begins_with("Previous Visitor"))
	assert_eq(column.get_child(0).get_child(0).portrait, portrait)
	assert_eq(column.get_child(1).get_child(0).portrait, portrait)
	column.get_child(1).get_child(0).pressed.emit()
	assert_eq(toolbar._visitor_detail.get_child(1).texture, portrait, "Profile uses the same skin snapshot")

func test_course_click_opens_full_profile_without_popup() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	var golfer := Golfer.new()
	golfer.golfer_name = "Full Profile Visitor"
	golfer.attributes.profession = "Architect"
	golfer.hole_scores.append({"hole": 3, "strokes": 4, "par": 5})
	golfer.activity_text = "Walking to the tee"
	toolbar.golfer_data_provider = func(): return [{"name": golfer.golfer_name, "profile": main._visitor_profile(golfer)}]
	toolbar.collapse_section()
	main._on_golfer_clicked(golfer)
	assert_eq(toolbar.current_tab, TerrainToolbar.Tab.GOLFERS)
	assert_false(toolbar.section_collapsed)
	assert_eq(toolbar._selected_visitor, golfer.golfer_name)
	assert_true(toolbar._visitor_detail.visible)
	assert_null(main.get_node_or_null("UI/HUD/GolferInfoPopup"), "The old popup is no longer created")
	var sections: Array = toolbar._visitor_archive[golfer.golfer_name].profile
	var titles: Array = []
	for section in sections:
		titles.append(section.title)
	for title in ["Identity", "Club Membership", "Golfer Traits", "Golfer Skills", "Golf Skills", "Golfer Statuses", "Golfer Comments", "Course Experience", "Current Round", "Scorecard"]:
		assert_has(titles, title)
	assert_string_contains(sections[0].lines[0], "Architect")
	assert_string_contains(_section(sections, "Scorecard").lines[0], "H3: 4 strokes / par 5")
	golfer.attributes.energy = 0.25
	toolbar._refresh_golfer_lists()
	assert_eq(_section(toolbar._visitor_archive[golfer.golfer_name].profile, "Golfer Statuses").meters.Energy, 0.25, "Active profile updates live")
	# The archive remains readable after the golfer leaves and is freed.
	toolbar.golfer_data_provider = func(): return []
	golfer.free()
	toolbar._refresh_golfer_lists()
	assert_eq(_section(toolbar._visitor_archive["Full Profile Visitor"].profile, "Golfer Statuses").meters.Energy, 0.25)

## The profile section with this title (the sections are found by name, so a
## new section does not shift the test's expectations).
func _section(sections: Array, title: String) -> Dictionary:
	for section in sections:
		if str(section.title) == title:
			return section
	return {}

func test_refresh_keeps_focus_on_the_focused_visitor() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	toolbar._visitor_archive.clear()
	toolbar._selected_visitor = ""
	toolbar.golfer_data_provider = func(): return [{"id": 7, "name": "Ada Green", "tier": 1, "hole": 2, "strokes": 5}]
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	var card: HBoxContainer = toolbar._visitor_shelf.get_child(0).get_child(0)
	var plate := card.get_child(0) as VisitorCardButton
	plate.grab_focus()
	assert_eq(get_viewport().gui_get_focus_owner(), plate,
		"The keyboard/gamepad focus sits on the plate")
	# The one-second refresh leaves a register that would draw the same
	# plates alone, so the selector is never pulled off the button.
	toolbar._refresh_golfer_lists()
	toolbar._refresh_golfer_lists()
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_eq(focus_owner, plate, "The refresh keeps the same plate focused")
	# A refresh that must rebuild the register (a past visitor joined the
	# archive) puts the focus back on the same visitor's new plate.
	toolbar.record_completed_round({"name": "Someone Else", "strokes": 72, "par": 72, "day": 1})
	focus_owner = get_viewport().gui_get_focus_owner()
	assert_not_null(focus_owner, "The rebuild restores the focus")
	if focus_owner is VisitorCardButton:
		assert_eq((focus_owner as VisitorCardButton).text, "Ada Green",
			"and it lands on the same visitor's plate")

func test_refresh_keeps_focus_inside_the_open_profile() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	toolbar._visitor_archive.clear()
	toolbar._selected_visitor = ""
	toolbar.golfer_data_provider = func(): return [{"id": 8, "name": "Bea Bunker", "tier": 1, "hole": 1, "strokes": 2}]
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	var card: HBoxContainer = toolbar._visitor_shelf.get_child(0).get_child(0)
	(card.get_child(0) as Button).pressed.emit()
	assert_true(toolbar._visitor_detail.visible)
	# The back button is the profile's way out; the one-second refresh rebuilds
	# the profile too, so it must hand the focus back to the rebuilt button.
	var back := toolbar._visitor_detail.get_child(0) as Button
	back.grab_focus()
	toolbar._refresh_golfer_lists()
	var focus_owner := get_viewport().gui_get_focus_owner()
	assert_not_null(focus_owner, "The refresh restores the dropped focus")
	assert_true(focus_owner == toolbar._visitor_detail.get_child(0),
		"and it sits on the rebuilt way-back button")

## The profile follows a live round without being torn down when nothing
## moved: a quiet refresh leaves the same card row standing, while a golfer
## who moved on is drawn again with their new numbers.
func test_a_quiet_refresh_leaves_the_open_profile_standing() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	toolbar._visitor_archive.clear()
	toolbar._selected_visitor = ""
	toolbar.golfer_data_provider = func(): return [{"id": 21, "name": "Cleo Tee",
		"tier": 1, "hole": 2, "strokes": 5, "attitude": 0.5}]
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	var plate := toolbar._visitor_shelf.get_child(0).get_child(0).get_child(0) as Button
	plate.pressed.emit()
	var identity := toolbar._visitor_detail.get_child(1) as VisitorIdentityCard
	assert_not_null(identity, "The identity card opened")

	toolbar._refresh_golfer_lists()
	assert_eq(toolbar._visitor_detail.get_child(1), identity,
		"A refresh with nothing new leaves the same cards in place")

	toolbar.golfer_data_provider = func(): return [{"id": 21, "name": "Cleo Tee",
		"tier": 1, "hole": 6, "strokes": 21, "attitude": 0.9}]
	toolbar._refresh_golfer_lists()
	var rebuilt := toolbar._visitor_detail.get_child(1) as VisitorIdentityCard
	assert_not_null(rebuilt, "A golfer who moved on is drawn again")
	assert_ne(rebuilt, identity, "with a fresh card row")
	assert_true(_has_label_text(rebuilt, "90%") or _has_label_text(toolbar._visitor_detail, "90%"),
		"and the new attitude is on it")

## The Locate chip floats over the golfer's portrait in the identity card and
## is a separate action from the profile: pressing it moves the camera and
## leaves the profile open.
func test_the_profile_locate_chip_is_a_separate_action() -> void:
	var toolbar: TerrainToolbar = main.terrain_toolbar
	toolbar._visitor_archive.clear()
	toolbar._selected_visitor = ""
	toolbar.golfer_data_provider = func(): return [{"id": 22, "name": "Dana Drive",
		"tier": 1, "hole": 3, "strokes": 7, "attitude": 0.5}]
	toolbar.select_tab(TerrainToolbar.Tab.GOLFERS)
	(toolbar._visitor_shelf.get_child(0).get_child(0).get_child(0) as Button).pressed.emit()
	var locate := _profile_locate(toolbar._visitor_detail)
	assert_not_null(locate, "An on-course golfer's profile carries a Locate chip")
	watch_signals(toolbar)
	locate.pressed.emit()
	assert_signal_emitted_with_parameters(toolbar, "golfer_row_clicked", [22])
	assert_eq(toolbar._selected_visitor, "Dana Drive",
		"Locating from the profile leaves the profile open")

## The Locate chip inside an open profile, if there is one.
func _profile_locate(root: Node) -> Button:
	for child in root.get_children():
		if child is Button and (child as Button).tooltip_text.begins_with("Center the camera on "):
			return child as Button
		var found := _profile_locate(child)
		if found != null:
			return found
	return null

## Whether any label under `root` reads `text`.
func _has_label_text(root: Node, text: String) -> bool:
	for child in root.get_children():
		if child is Label and (child as Label).text == text:
			return true
		if _has_label_text(child, text):
			return true
	return false
