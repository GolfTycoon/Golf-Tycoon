extends GameTest
## Loading a save checks what it reads: values out of range are clamped, and a
## field that is missing — or damaged, holding null or text where a number
## belongs — takes its default instead of stopping the load half way. Every test
## goes through SaveManager._apply_save_data(), the loader itself.

var _saved_world: Dictionary
var _saved_experience: Dictionary
var _saved_terrain_grid: TerrainGrid

func before_each() -> void:
	super()
	_saved_world = WorldMap.serialize()
	_saved_experience = FeedbackManager.serialize_experience()
	_saved_terrain_grid = SaveManager.terrain_grid

func after_each() -> void:
	SaveManager._is_loading = false
	SaveManager.terrain_grid = _saved_terrain_grid
	WorldMap.deserialize(_saved_world)
	FeedbackManager.restore_experience(_saved_experience)
	super()
	# The loader repaints the terrain palette for the theme it read.
	TerrainPalette.set_theme_colors(CourseTheme.get_terrain_colors(GameManager.current_theme))

## Load a save whose game state is `game_state`, the way a save file is loaded.
func _load(game_state: Variant) -> void:
	GameManager.current_course = GameManager.CourseData.new()
	SaveManager._apply_save_data({
		"version": SaveManager.SAVE_VERSION,
		"game_state": game_state,
		"world_map": WorldMap.serialize(),
	})


# ---------------------------------------------------------------------------
# Values out of range
# ---------------------------------------------------------------------------

func test_reputation_is_clamped_to_its_range() -> void:
	_load({"reputation": 150.0})
	assert_eq(GameManager.reputation, 100.0, "Above 100 loads as 100")
	_load({"reputation": -20.0})
	assert_eq(GameManager.reputation, 0.0, "Below 0 loads as 0")
	_load({"reputation": 65.5})
	assert_almost_eq(GameManager.reputation, 65.5, 0.001, "A valid reputation is kept")

func test_the_day_is_never_before_day_one() -> void:
	_load({"current_day": 0})
	assert_eq(GameManager.current_day, 1)
	_load({"current_day": -5})
	assert_eq(GameManager.current_day, 1)
	_load({"current_day": 42})
	assert_eq(GameManager.current_day, 42)

func test_the_green_fee_is_clamped_to_its_range() -> void:
	_load({"green_fee": GameManager.MIN_GREEN_FEE - 1})
	assert_eq(GameManager.green_fee, GameManager.MIN_GREEN_FEE, "Below the minimum loads as the minimum")
	_load({"green_fee": 999})
	assert_eq(GameManager.green_fee, GameManager.MAX_GREEN_FEE, "Above the maximum loads as the maximum")
	_load({"green_fee": 50})
	assert_eq(GameManager.green_fee, 50, "A valid fee is kept")

func test_the_booking_interval_is_clamped_to_its_range() -> void:
	_load({"tee_booking_interval": 5})
	assert_eq(GameManager.tee_booking_interval, 60)
	_load({"tee_booking_interval": 1000})
	assert_eq(GameManager.tee_booking_interval, 180)


# ---------------------------------------------------------------------------
# Missing and damaged values
# ---------------------------------------------------------------------------

func test_an_empty_game_state_uses_every_default() -> void:
	_load({})
	assert_eq(GameManager.course_name, "Loaded Course")
	assert_eq(GameManager.money, GameManager.DEFAULT_STARTING_MONEY)
	assert_almost_eq(GameManager.reputation, GameManager.DEFAULT_STARTING_REPUTATION, 0.001)
	assert_eq(GameManager.current_day, 1)
	assert_eq(GameManager.tee_booking_interval, 90)
	assert_eq(GameManager.current_difficulty, DifficultyPresets.Preset.NORMAL)
	assert_eq(GameManager.current_theme, CourseTheme.Type.PARKLAND)

## JSON stores a damaged field as null, and Dictionary.get() then returns the
## null rather than the default. int(null) used to stop the load half way,
## leaving the game half loaded with SaveManager stuck in its loading state.
func test_null_fields_load_as_their_defaults() -> void:
	_load({"course_name": null, "money": null, "reputation": null, "current_day": null,
		"green_fee": null, "difficulty": null, "theme": null})
	assert_eq(GameManager.course_name, "Loaded Course")
	assert_eq(GameManager.money, GameManager.DEFAULT_STARTING_MONEY)
	assert_almost_eq(GameManager.reputation, GameManager.DEFAULT_STARTING_REPUTATION, 0.001)
	assert_eq(GameManager.current_day, 1)
	assert_eq(GameManager.green_fee, 30)
	assert_false(SaveManager._is_loading, "The load ran to the end")
	assert_eq(GameManager.current_mode, GameManager.GameMode.SIMULATING, "and the course is back in play")

func test_text_where_a_number_belongs_loads_as_the_default() -> void:
	_load({"money": "lots", "reputation": "high", "current_day": "monday"})
	assert_eq(GameManager.money, GameManager.DEFAULT_STARTING_MONEY)
	assert_almost_eq(GameManager.reputation, GameManager.DEFAULT_STARTING_REPUTATION, 0.001)
	assert_eq(GameManager.current_day, 1)

func test_a_game_state_that_is_not_a_dictionary_is_ignored() -> void:
	_load(null)
	assert_eq(GameManager.money, GameManager.DEFAULT_STARTING_MONEY)
	assert_false(SaveManager._is_loading)


# ---------------------------------------------------------------------------
# What the save carries
# ---------------------------------------------------------------------------

func test_saved_values_survive_a_json_round_trip() -> void:
	var state: Dictionary = JSON.parse_string(JSON.stringify({
		"course_name": "Test Links", "money": 75000, "reputation": 65.5,
		"current_day": 15, "green_fee": 45, "difficulty": "hard", "theme": "links",
	}))
	_load(state)
	assert_eq(GameManager.course_name, "Test Links")
	assert_eq(GameManager.money, 75000, "JSON's floats load back as whole dollars")
	assert_almost_eq(GameManager.reputation, 65.5, 0.001)
	assert_eq(GameManager.current_day, 15)
	assert_eq(GameManager.green_fee, 45)
	assert_eq(GameManager.current_difficulty, DifficultyPresets.Preset.HARD)
	assert_eq(GameManager.bankruptcy_threshold, 0, "The difficulty brings its overdraft limit")
	assert_eq(GameManager.current_theme, CourseTheme.Type.LINKS)

func test_legacy_deep_bunker_data_is_ignored_and_not_saved_again() -> void:
	var grid := make_grid(8, 8)
	SaveManager.terrain_grid = grid
	GameManager.current_course = GameManager.CourseData.new()
	var legacy_world := WorldMap.serialize()
	legacy_world["snapshots"] = {
		"legacy-site": {"terrain": {"3,3": TerrainTypes.Type.BUNKER}, "bunker_depth": {"3,3": 1}},
	}
	SaveManager._apply_save_data({
		"version": SaveManager.SAVE_VERSION,
		"game_state": {},
		"world_map": legacy_world,
		"terrain": {"3,3": TerrainTypes.Type.BUNKER},
		"bunker_depth": {"3,3": 1},
	})

	assert_eq(grid.get_tile(Vector2i(3, 3)), TerrainTypes.Type.BUNKER)
	assert_eq(grid._course_surface._data.get_pixel(3, 3).g, 0.0,
		"Legacy deep metadata cannot change the shallow bunker surface")
	var saved := SaveManager._build_save_data()
	assert_false(saved.has("bunker_depth"), "New saves no longer write the retired field")
	assert_false(saved["world_map"]["snapshots"]["legacy-site"].has("bunker_depth"),
		"Old site snapshots discard the retired field too")

func test_a_version_one_save_keeps_its_state_at_the_top_level() -> void:
	GameManager.current_course = GameManager.CourseData.new()
	SaveManager._apply_save_data({"course_name": "Flat Save", "money": 1234,
		"world_map": WorldMap.serialize()})
	assert_eq(GameManager.course_name, "Flat Save")
	assert_eq(GameManager.money, 1234)

# ---------------------------------------------------------------------------
# The owner's own ground
# ---------------------------------------------------------------------------

func test_the_owners_work_area_is_restored_with_the_course() -> void:
	# The ground the owner's own golfer works belongs to the course, so it is
	# saved with the site and comes back when the course is loaded.
	var grid := make_grid(32, 32)
	GameManager.terrain_grid = grid
	var owner_manager := PlayerGolferManager.new()
	add_child_autofree(owner_manager)
	GameManager.player_golfer_manager = owner_manager
	assert_true(owner_manager.set_area_center(Vector2i(7, 9)))
	owner_manager.set_area_center(Vector2i(20, 20))

	GameManager.current_course = GameManager.CourseData.new()
	SaveManager._apply_save_data({
		"version": SaveManager.SAVE_VERSION,
		"game_state": {},
		"world_map": WorldMap.serialize(),
		"owner_duty": {"area_center": {"x": 7, "y": 9}, "area_radius": 8.0},
	})
	assert_eq(owner_manager.area_center, Vector2i(7, 9),
		"The ground the owner works comes back with the course")
