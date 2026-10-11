extends GameTest
## The land the course stands on: the parcel grid tiles belong to (the margin
## round the grid belongs to none), which parcels can be bought, what they cost
## and how ownership is saved.

var land: LandManager

func before_each() -> void:
	super()
	GameManager.current_theme = CourseTheme.Type.PARKLAND
	land = LandManager.new()
	add_child_autofree(land)  # _ready() grants the centre 2x2 parcels


# ---------------------------------------------------------------------------
# Tiles and parcels
# ---------------------------------------------------------------------------

## tile_to_parcel folded the grid margin and negative tiles into parcel 0, so
## off-grid tiles could read as owned land.
func test_tile_to_parcel_maps_margin_tiles_off_grid() -> void:
	# The grid starts at tile GRID_OFFSET (4). Tiles before it are not on any parcel.
	assert_eq(land.tile_to_parcel(Vector2i(0, 0)), Vector2i(-1, -1), "Corner margin tile is off-grid")
	assert_eq(land.tile_to_parcel(Vector2i(3, 3)), Vector2i(-1, -1), "Last margin tile is off-grid")
	assert_eq(land.tile_to_parcel(Vector2i(-5, 10)), Vector2i(-1, -1), "Negative tile is off-grid")

func test_tile_to_parcel_still_maps_on_grid_tiles() -> void:
	assert_eq(land.tile_to_parcel(Vector2i(4, 4)), Vector2i(0, 0), "First on-grid tile is parcel (0,0)")
	assert_eq(land.tile_to_parcel(Vector2i(23, 4)), Vector2i(0, 0), "Last tile of the first parcel")
	assert_eq(land.tile_to_parcel(Vector2i(24, 4)), Vector2i(1, 0), "First tile of the next parcel")

func test_margin_tiles_are_not_owned_when_corner_parcel_is_owned() -> void:
	land.owned_parcels[Vector2i(0, 0)] = true
	assert_false(land.is_tile_owned(Vector2i(1, 1)), "Margin tile must not count as owned land")
	assert_false(land.is_tile_owned(Vector2i(-3, 2)), "Negative tile must not count as owned land")
	assert_true(land.is_tile_owned(Vector2i(5, 5)), "A tile inside an owned parcel is owned")

func test_a_parcel_covers_its_own_square_of_tiles() -> void:
	var rect := land.parcel_to_tile_rect(Vector2i(2, 3))
	assert_eq(rect, Rect2i(44, 64, 20, 20))
	assert_eq(land.tile_to_parcel(rect.position), Vector2i(2, 3))
	assert_eq(land.tile_to_parcel(rect.end - Vector2i.ONE), Vector2i(2, 3))


# ---------------------------------------------------------------------------
# Buying land
# ---------------------------------------------------------------------------

func test_a_new_course_owns_the_centre_four_parcels() -> void:
	for parcel in [Vector2i(2, 2), Vector2i(2, 3), Vector2i(3, 2), Vector2i(3, 3)]:
		assert_true(land.owned_parcels.has(parcel), "%s is owned from the start" % parcel)
	assert_eq(land.get_owned_tile_count(), 4 * 20 * 20)

func test_only_parcels_next_to_owned_land_can_be_bought() -> void:
	assert_true(land.is_parcel_purchasable(Vector2i(1, 2)), "A neighbour of the start can be bought")
	assert_false(land.is_parcel_purchasable(Vector2i(0, 0)), "A far corner cannot")
	assert_false(land.is_parcel_purchasable(Vector2i(2, 2)), "Owned land cannot be bought again")
	assert_false(land.is_parcel_purchasable(Vector2i(-1, 2)), "Nor land off the grid")
	assert_eq(land.can_purchase_parcel(Vector2i(2, 2)).reason, "Already owned")
	assert_eq(land.can_purchase_parcel(Vector2i(0, 0)).reason, "Not adjacent to owned land")

func test_a_location_limits_the_land_on_offer() -> void:
	land.set_location_parcels([Vector2i(2, 2), Vector2i(3, 2), Vector2i(1, 2)])
	assert_true(land.is_parcel_purchasable(Vector2i(1, 2)), "Inside the location's block")
	assert_false(land.is_parcel_purchasable(Vector2i(4, 2)), "Outside it, though adjacent")

func test_buying_a_parcel_charges_its_price_and_the_next_one_costs_more() -> void:
	GameManager.money = 1000000
	var parcel := Vector2i(1, 2)
	var price := land.get_parcel_cost(parcel)
	var base_before := land.get_parcel_cost()
	assert_true(land.purchase_parcel(parcel))
	assert_true(land.owned_parcels.has(parcel))
	assert_eq(GameManager.money, 1000000 - price, "The parcel is paid for")
	assert_eq(land.get_parcel_cost(), int(LandManager.BASE_PARCEL_COST * LandManager.COST_ESCALATION),
		"Each purchase raises the price of the next")
	assert_gt(land.get_parcel_cost(), base_before)

func test_land_the_company_cannot_afford_is_refused() -> void:
	GameManager.money = 0
	GameManager.bankruptcy_threshold = 0
	var parcel := Vector2i(1, 2)
	assert_false(land.can_purchase_parcel(parcel).can_buy)
	assert_false(land.purchase_parcel(parcel))
	assert_false(land.owned_parcels.has(parcel))
	assert_eq(GameManager.money, 0, "Nothing is charged")

func test_ownership_survives_a_save_round_trip() -> void:
	GameManager.money = 1000000
	land.purchase_parcel(Vector2i(1, 2))
	land.mark_features_generated(Vector2i(1, 2))
	land.set_location_parcels([Vector2i(1, 2), Vector2i(2, 2)])
	var saved: Dictionary = JSON.parse_string(JSON.stringify(land.serialize()))

	var loaded := LandManager.new()
	add_child_autofree(loaded)
	loaded.deserialize(saved)
	assert_eq(loaded.owned_parcels.keys().size(), land.owned_parcels.keys().size())
	assert_true(loaded.owned_parcels.has(Vector2i(1, 2)))
	assert_true(loaded.has_features_generated(Vector2i(1, 2)))
	assert_true(loaded.is_parcel_in_location(Vector2i(2, 2)))
	assert_false(loaded.is_parcel_in_location(Vector2i(5, 5)))
	assert_eq(loaded.get_parcel_cost(), land.get_parcel_cost(), "The price escalation is kept")
