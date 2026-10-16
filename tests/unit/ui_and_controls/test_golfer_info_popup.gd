extends GameTest
## The golfer popup's scorecard labels each score with the recorded course hole.

func test_scorecard_shows_the_recorded_hole_numbers() -> void:
	var golfer: Golfer = autofree(Golfer.new())
	golfer.hole_scores = [
		{"hole": 1, "strokes": 3, "par": 4},
		{"hole": 2, "strokes": 4, "par": 4},
	]
	var popup: GolferInfoPopup = add_child_autofree(GolferInfoPopup.new())
	popup.show_for_golfer(golfer)
	await process_frames(1)

	var grids := popup._content_vbox.find_children("*", "GridContainer", true, false)
	assert_eq(grids.size(), 1, "The completed holes appear in one scorecard grid")
	var grid := grids[0] as GridContainer
	assert_eq((grid.get_child(0) as Label).text, "H1",
		"Hole 1's score is labelled Hole 1")
	assert_eq((grid.get_child(3) as Label).text, "H2",
		"Hole 2's score is labelled Hole 2")
