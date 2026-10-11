extends GameTest
## The course and its holes as GameManager keeps them: CourseData adds up the par
## of its holes and lists the open ones, and a new HoleData starts as an open par
## 4.

func test_course_data_add_hole() -> void:
	var course = GameManager.CourseData.new()
	var hole = GameManager.HoleData.new()
	hole.par = 4
	course.add_hole(hole)
	assert_eq(course.holes.size(), 1, "Should have one hole")
	assert_eq(course.total_par, 4, "Total par should be 4")

func test_course_data_multiple_holes_par() -> void:
	var course = GameManager.CourseData.new()
	for par in [3, 4, 5, 4]:
		var hole = GameManager.HoleData.new()
		hole.par = par
		course.add_hole(hole)
	assert_eq(course.total_par, 16, "Total par should be sum: 3+4+5+4=16")

func test_course_data_get_open_holes() -> void:
	var course = GameManager.CourseData.new()
	for i in range(3):
		var hole = GameManager.HoleData.new()
		hole.hole_number = i + 1
		hole.is_open = (i != 1)  # Close hole 2
		course.add_hole(hole)
	assert_eq(course.get_open_holes().size(), 2, "Should have 2 open holes")

func test_the_open_hole_count_follows_the_current_course() -> void:
	GameManager.current_course = null
	assert_eq(GameManager.get_open_hole_count(), 0, "No course, no holes")
	var course = GameManager.CourseData.new()
	for open in [true, false, true, true]:
		var hole = GameManager.HoleData.new()
		hole.is_open = open
		course.add_hole(hole)
	GameManager.current_course = course
	assert_eq(GameManager.get_open_hole_count(), 3, "Closed holes are not counted")

func test_hole_data_defaults() -> void:
	var hole = GameManager.HoleData.new()
	assert_eq(hole.par, 4, "Default par should be 4")
	assert_true(hole.is_open, "Holes should be open by default")
	assert_eq(hole.difficulty_rating, 1.0, "Default difficulty should be 1.0")
