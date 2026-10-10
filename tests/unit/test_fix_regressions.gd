extends GutTest
## Regression tests for defects fixed in the game-logic review:
##  - LandManager.tile_to_parcel folded the grid margin and negative tiles into
##    parcel 0, so off-grid tiles could read as owned land.
##  - The bankruptcy notice always said "-$1,000", whatever the difficulty.
##  - yesterday_stats was copied field by field and dropped decoration costs.
##  - SaveManager.get_save_list stripped every ".save" from a name, not just the
##    extension.

const SAVE_DIR_PATH := "user://saves/"


# --- Land parcels --------------------------------------------------------------

func test_tile_to_parcel_maps_margin_tiles_off_grid() -> void:
	var lm := LandManager.new()
	# The grid starts at tile GRID_OFFSET (4). Tiles before it are not on any parcel.
	assert_eq(lm.tile_to_parcel(Vector2i(0, 0)), Vector2i(-1, -1), "Corner margin tile is off-grid")
	assert_eq(lm.tile_to_parcel(Vector2i(3, 3)), Vector2i(-1, -1), "Last margin tile is off-grid")
	assert_eq(lm.tile_to_parcel(Vector2i(-5, 10)), Vector2i(-1, -1), "Negative tile is off-grid")
	lm.free()


func test_tile_to_parcel_still_maps_on_grid_tiles() -> void:
	var lm := LandManager.new()
	assert_eq(lm.tile_to_parcel(Vector2i(4, 4)), Vector2i(0, 0), "First on-grid tile is parcel (0,0)")
	assert_eq(lm.tile_to_parcel(Vector2i(23, 4)), Vector2i(0, 0), "Last tile of the first parcel")
	assert_eq(lm.tile_to_parcel(Vector2i(24, 4)), Vector2i(1, 0), "First tile of the next parcel")
	lm.free()


func test_margin_tiles_are_not_owned_when_corner_parcel_is_owned() -> void:
	var lm := LandManager.new()
	lm.owned_parcels[Vector2i(0, 0)] = true
	assert_false(lm.is_tile_owned(Vector2i(1, 1)), "Margin tile must not count as owned land")
	assert_false(lm.is_tile_owned(Vector2i(-3, 2)), "Negative tile must not count as owned land")
	assert_true(lm.is_tile_owned(Vector2i(5, 5)), "A tile inside an owned parcel is owned")
	lm.free()


# --- Bankruptcy notice ----------------------------------------------------------

func test_spending_blocked_message_uses_the_difficulty_threshold() -> void:
	var saved: int = GameManager.bankruptcy_threshold
	GameManager.bankruptcy_threshold = -5000
	assert_eq(GameManager.spending_blocked_message(), "Spending blocked! Balance below -$5,000",
		"Easy's -$5,000 limit is shown")
	GameManager.bankruptcy_threshold = -1000
	assert_eq(GameManager.spending_blocked_message(), "Spending blocked! Balance below -$1,000",
		"Normal's -$1,000 limit is shown")
	GameManager.bankruptcy_threshold = 0
	assert_eq(GameManager.spending_blocked_message(), "Spending blocked! Balance below $0",
		"Hard's zero limit reads as $0, not -$0")
	GameManager.bankruptcy_threshold = saved


# --- Yesterday's statistics -----------------------------------------------------

func test_yesterday_stats_keep_every_cost_category() -> void:
	var saved_day: int = GameManager.current_day
	var saved_rep: float = GameManager.reputation
	var saved_history: Array = GameManager.daily_history.duplicate()
	var saved_yesterday = GameManager.yesterday_stats

	# Mid-year so the rollover does not trigger the year-end summary.
	GameManager.current_day = 100
	GameManager.daily_stats.reset()
	GameManager.daily_stats.revenue = 500
	GameManager.daily_stats.operating_costs = 90
	GameManager.daily_stats.decoration_operating_costs = 7
	GameManager.daily_stats.staff_wages = 40
	GameManager.daily_stats.tier_counts[GolferTier.Tier.PRO] = 3

	GameManager.advance_to_next_day()

	var yesterday := GameManager.yesterday_stats
	assert_not_null(yesterday, "Yesterday's stats are kept after rollover")
	assert_eq(yesterday.revenue, 500, "Revenue is carried over")
	assert_eq(yesterday.operating_costs, 90, "Operating costs are carried over")
	assert_eq(yesterday.decoration_operating_costs, 7, "Decoration costs are carried over")
	assert_eq(yesterday.staff_wages, 40, "Staff wages are carried over")
	assert_eq(yesterday.tier_counts[GolferTier.Tier.PRO], 3, "Tier counts are carried over")
	assert_eq(GameManager.daily_stats.revenue, 0, "The new day starts with zeroed stats")

	GameManager.current_day = saved_day
	GameManager.reputation = saved_rep
	GameManager.daily_history = saved_history
	GameManager.yesterday_stats = saved_yesterday
	GameManager.daily_stats.reset()


# --- Save list names -------------------------------------------------------------

func test_save_list_keeps_dots_inside_the_save_name() -> void:
	DirAccess.make_dir_recursive_absolute(SAVE_DIR_PATH)
	var path := SAVE_DIR_PATH + "my.save.v2.save"
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(JSON.stringify({"timestamp": "2000-01-01T00:00:00", "game_state": {"course_name": "X", "current_day": 1}}))
	file.close()

	var names: Array = []
	for entry in SaveManager.get_save_list():
		names.append(entry.get("name", ""))
	DirAccess.remove_absolute(path)

	assert_true(names.has("my.save.v2"), "The name keeps its inner '.save' text")
