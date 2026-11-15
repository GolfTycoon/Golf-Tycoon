extends GameTest
## Favourite colours: the colour each golfer has picked for themselves, and the
## ring drawn on the ground beneath them that wears it.
##
## Every golfer has one - the course owner on the Edit Player Golfer page, a
## visitor on their card in `data/visiting_golfers/`, and every golfer the game
## rolls itself - and it is part of the person rather than of their Golfer Skin:
## two golfers wearing one kit are still told apart on the course by the ring
## under them (see GolferFavouriteColour).

const GOLFER_SCENE := preload("res://scenes/entities/golfer.tscn")
const COLOUR_FIELD := "favourite_colour"

## A golfer standing in a small world, so the ring it builds is in the tree.
func _golfer() -> Golfer:
	var world := Node2D.new()
	world.name = "World"
	add_child_autofree(world)
	var golfer := GOLFER_SCENE.instantiate() as Golfer
	world.add_child(golfer)
	golfer.set_process(false)
	golfer.set_physics_process(false)
	return golfer


# ---------------------------------------------------------------------------
# What a favourite colour is
# ---------------------------------------------------------------------------

func test_a_stored_colour_is_read_in_every_form_the_game_writes_one_in() -> void:
	var colour := GolferFavouriteColour.parse("e94f37")
	assert_almost_eq(colour.r, Color("e94f37").r, 0.001)
	assert_almost_eq(colour.g, Color("e94f37").g, 0.001)
	assert_almost_eq(colour.b, Color("e94f37").b, 0.001)
	assert_eq(colour, GolferFavouriteColour.parse("#e94f37"),
		"the # a hand-written card uses makes no difference")
	assert_eq(colour, GolferFavouriteColour.parse(Color("e94f37")),
		"a Color is already the colour")
	assert_eq(GolferFavouriteColour.parse("not a colour", Color("29bbaa")), Color("29bbaa"),
		"a value that is not a colour leaves the fallback")
	assert_eq(GolferFavouriteColour.parse("", Color("e94f37")), Color("e94f37"),
		"an empty value is not a colour either")

func test_a_colour_is_written_as_the_hex_the_rest_of_a_golfer_is() -> void:
	assert_eq(GolferFavouriteColour.to_field(Color("4EA5D9")), "4ea5d9",
		"A favourite is stored as lowercase hex with no #, like a kit colour")
	assert_eq(GolferFavouriteColour.parse("4ea5d9", Color.WHITE).a, 1.0,
		"A favourite colour is never see-through")

func test_the_ring_under_a_golfer_is_its_favourite_colour() -> void:
	var golfer := _golfer()
	golfer.set_favourite_colour(Color("b06ab3"))
	var ring := golfer.get_node_or_null("FavouriteRing") as Polygon2D
	assert_not_null(ring, "Every golfer wears a ring on the ground")
	assert_eq(Color(ring.color.r, ring.color.g, ring.color.b), Color("b06ab3"),
		"The ring is the colour the golfer picked")
	assert_eq(golfer.favourite_colour(), Color("b06ab3"),
		"and the golfer says so themselves")

## The ring is a band, not a disc: its polygon walks the outside and comes back
## around the inside, so the shadow under the golfer's feet stays visible inside
## it and only a ring of colour is drawn.
func test_the_ring_leaves_a_hole_for_the_shadow_it_rings() -> void:
	var golfer := _golfer()
	var ring := golfer.get_node("FavouriteRing") as Polygon2D
	var outer_max := 0.0
	var inner_min := INF
	for point in ring.polygon:
		outer_max = maxf(outer_max, point.length())
		inner_min = minf(inner_min, point.length())
	assert_eq(ring.polygon.size(), 56, "The ring is 28 points outside and 28 inside")
	assert_gt(inner_min, 0.0, "There is an inside edge to the band")
	assert_almost_eq(inner_min / outer_max, 0.42, 0.05,
		"The band is an outline around the feet, not a filled disc")

func test_a_golfer_with_no_colour_of_their_own_takes_their_kits() -> void:
	var golfer := _golfer()
	# A golfer the game rolls has no card to pick a colour for them, and the
	# ring is still theirs: it takes the colour of the kit they wear.
	assert_gt(golfer.favourite_colour().a, 0.0,
		"A golfer is never drawn with a ring nobody can see")
	# Their kit's shirt is the first colour a favourite is taken from.
	var shirt := golfer._favourite_colour_from_kit()
	assert_gt(shirt.a, 0.0)

func test_a_kit_that_reads_on_the_ground_supplies_the_favourite() -> void:
	# Shirt first; a shirt too dark to read as a ring steps down to the cap.
	assert_eq(GolferFavouriteColour.from_kit({"Shirt": Color("4ea5d9")}), Color("4ea5d9"))
	assert_eq(GolferFavouriteColour.from_kit({
		"Shirt": Color("0b0b0b"), "Cap": Color("f2b134")}), Color("f2b134"),
		"A nearly black shirt is passed over for a colour that reads")
	assert_eq(GolferFavouriteColour.from_kit({"Shirt": Color("fefefe"), "Pants": Color("7bc950")}),
		Color("7bc950"), "and so is a nearly white one")
	var seeded := GolferFavouriteColour.from_kit({}, 3)
	assert_true(seeded in GolferFavouriteColour.PALETTE,
		"A kit with no readable colour falls back to the palette")
	assert_eq(seeded, GolferFavouriteColour.from_kit({}, 3),
		"and the same golfer keeps the same colour")


# ---------------------------------------------------------------------------
# Where the colour lives
# ---------------------------------------------------------------------------

func test_the_attribute_block_carries_the_favourite_colour() -> void:
	var attributes := GolferAttributes.new()
	attributes.generate_for_tier(GolferTier.Tier.CASUAL)
	assert_gt(attributes.favourite_colour.a, 0.0,
		"A rolled golfer has a favourite colour, like a name")
	var restored := GolferAttributes.from_data(
		JSON.parse_string(JSON.stringify(attributes.serialize())))
	assert_eq(restored.favourite_colour, attributes.favourite_colour,
		"The colour survives being written to a save and read back")
	assert_eq(str(attributes.serialize()[COLOUR_FIELD]),
		attributes.favourite_colour.to_html(false),
		"It is written in the field a visitor card names it in")

func test_a_visitor_card_sets_the_golfers_favourite_colour() -> void:
	var attributes := GolferAttributes.new()
	attributes.generate_for_tier(GolferTier.Tier.CASUAL)
	attributes.apply_visitor_card({COLOUR_FIELD: "ef6f9b"})
	assert_eq(attributes.favourite_colour, Color("ef6f9b"),
		"The card's favourite colour is the golfer's")
	# The American spelling is accepted, because not every card is written by
	# the game (see GolferFavouriteColour).
	attributes.apply_visitor_card({"favorite_color": "29bbaa"})
	assert_eq(attributes.favourite_colour, Color("29bbaa"),
		"A card may spell the field the American way")

func test_a_card_without_a_colour_keeps_the_one_the_golfer_has() -> void:
	var attributes := GolferAttributes.new()
	attributes.generate_for_tier(GolferTier.Tier.CASUAL)
	attributes.favourite_colour = Color("f2b134")
	attributes.apply_visitor_card({"name": "Only A Name"})
	assert_eq(attributes.favourite_colour, Color("f2b134"),
		"A partial card never takes a golfer's colour away")

func test_the_owner_picks_their_colour_on_the_profile() -> void:
	var profile := PlayerGolferProfile.new()
	assert_eq(profile.favourite_colour, "", "An owner starts with no colour picked")
	profile.set_favourite_colour(Color("8a7df2"))
	assert_eq(profile.favourite_color(), Color("8a7df2"))
	var restored := PlayerGolferProfile.from_data(
		JSON.parse_string(JSON.stringify(profile.serialize())))
	assert_eq(restored.favourite_colour, "8a7df2",
		"The owner's favourite colour is saved with the rest of their profile")
	assert_eq(PlayerGolferProfile.from_data({}).favourite_colour, "",
		"A profile written before favourite colours existed carries none")


# ---------------------------------------------------------------------------
# The color the golfer on the course wears
# ---------------------------------------------------------------------------

func test_the_owners_golfer_wears_the_profiles_favourite_colour() -> void:
	var golfer := _golfer()
	var profile := PlayerGolferProfile.new()
	profile.set_favourite_colour(Color("ff8c42"))
	golfer.player_profile = profile
	golfer.apply_player_appearance(profile)
	assert_eq(golfer.favourite_colour(), Color("ff8c42"),
		"The owner's golfer wears the colour they picked")
	var ring := golfer.get_node("FavouriteRing") as Polygon2D
	assert_eq(Color(ring.color.r, ring.color.g, ring.color.b), Color("ff8c42"),
		"and the ring says so")

func test_a_saved_golfer_keeps_the_colour_they_picked() -> void:
	var saved := _golfer()
	saved.golfer_name = "Saved Golfer"
	saved.set_favourite_colour(Color("7bc950"))
	var data := saved.serialize()
	assert_eq(str(data[COLOUR_FIELD]), "7bc950",
		"A saved golfer carries their favourite colour in the entry")
	var restored := _golfer()
	restored.deserialize(JSON.parse_string(JSON.stringify(data)))
	assert_eq(restored.favourite_colour(), Color("7bc950"),
		"and comes back wearing it")

func test_the_owners_golfer_without_a_pick_takes_the_kits_colour() -> void:
	var golfer := _golfer()
	var profile := PlayerGolferProfile.new()
	golfer.player_profile = profile
	golfer.apply_player_appearance(profile)
	assert_gt(golfer.favourite_colour().a, 0.0,
		"An owner who has not picked a colour still has a ring to see")
