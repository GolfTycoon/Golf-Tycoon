extends RefCounted
class_name GolferFavouriteColour
## GolferFavouriteColour - every golfer's Favourite Colour, and where it shows.
##
## Every golfer in Golf Tycoon - a visiting guest, a tournament player, or the
## course owner - has a favourite colour. It is part of the person, not of the
## kit: the golfer's Golfer Skin dresses them (see GolferSkins), their visitor
## card's `group_colors` or the owner's profile picks the groups, and the
## favourite colour is the one they have picked for themselves. It is worn
## where a golfer is not their clothes: the ring drawn on the ground beneath
## them (the golfer's `FavouriteRing`, built by Golfer._create_ground_ring).
##
## The colour is stored as a hex string (`to_html(false)`: `rrggbb`, no `#`),
## the way the rest of the game writes a golfer's colours, so a card, a save
## file and the player profile all carry it in the same shape.
##
## Three pieces of the game hand it around:
##   - Visiting golfer cards in `data/visiting_golfers/<location>.json` carry a
##     `favourite_colour` (`favourite_color` is accepted too), read by
##     GolferAttributes.apply_visitor_card().
##   - A golfer with no colour of their own - every golfer the game rolls, and
##     every save written before golfer favourite colours existed - is given
##     one: the colour of their kit that reads best on the turf under them.
##   - The course owner picks theirs on the Edit Player Golfer page, where it
##     is written to the player profile beside their other colours.

## The card / save / profile field, spelled the way the game's own English
## spells it. The American spelling is accepted when reading, because mods and
## hand-written cards are not always written by the game.
const FIELD: String = "favourite_colour"
const AMERICAN_FIELD: String = "favorite_color"

## The palette a golfer with no colour of their own is given one from. Every
## colour is bright enough to read as a ring on grass, sand and the walking
## trail alike, and strong enough to tell two golfers apart at a glance. They
## are favourite colours, not terrain: a golfer may pick the same green the
## fairway wears.
const PALETTE: Array[Color] = [
	Color("e94f37"),  # Vermilion
	Color("f2b134"),  # Marigold
	Color("4ea5d9"),  # Sky
	Color("7bc950"),  # Fairway green
	Color("b06ab3"),  # Amethyst
	Color("ef6f9b"),  # Rose
	Color("29bbaa"),  # Teal
	Color("f4f1bb"),  # Cream
	Color("8a7df2"),  # Violet
	Color("ff8c42"),  # Tangerine
]


## The colour a stored value stands for: a hex string (`rrggbb`, with or
## without the `#`, or with an alpha pair) or a Color, with `fallback` when the
## value names neither. Never returns a transparent colour: a ring nothing can
## see is worse than a golfer with an ordinary favourite.
static func parse(value: Variant, fallback: Color = PALETTE[0]) -> Color:
	var colour := fallback
	if value is Color:
		colour = value
	elif value is String and not (value as String).strip_edges().is_empty():
		var text := (value as String).strip_edges().trim_prefix("#")
		if Color.html_is_valid(text):
			colour = Color.html(text)
	# Read from a copy so the caller's constant is never made opaque in place.
	if colour.a < 1.0:
		colour.a = 1.0
	return colour


## How a colour is stored: lowercase hex with no `#`, e.g. `"e94f37"`.
static func to_field(colour: Color) -> String:
	return colour.to_html(false)


## The field name a card or save carries the colour under, whether the card
## spells it the game's way or the American way, or "" when it carries neither.
static func field_in(data: Dictionary) -> String:
	if data.has(FIELD):
		return FIELD
	if data.has(AMERICAN_FIELD):
		return AMERICAN_FIELD
	return ""


## The colour a golfer's own kit suggests, for a golfer who has not picked one:
## the first of their Shirt, Cap, Pants and Hair - the parts of a kit a golfer
## chooses - that still reads as a ring on the ground. `kit` maps the names the
## game gives its groups (Shirt, Pants, Cap, Hair, Skin, and any group a skin
## adds - see GolferSkin) to Colors; a group the four do not name is used only
## after them, so a skin with a custom group still colours its golfers.
##
## A kit with no usable colour at all falls back to the palette, drawn by
## `seed` so the golfer still gets a stable colour of their own.
static func from_kit(kit: Dictionary, seed_value: int = 0) -> Color:
	# Nearly black and nearly white read as grit on the ground rather than as
	# somebody's favourite, and Skin is the person rather than their kit.
	var readable := func(colour: Color) -> bool:
		return colour.v > 0.18 and colour.v < 0.97
	for group_name in ["Shirt", "Cap", "Pants", "Hair"]:
		if not kit.has(group_name):
			continue
		var colour: Color = kit[group_name]
		colour.a = 1.0
		if readable.call(colour):
			return colour
	for group_name in kit:
		if str(group_name).to_lower() == "skin":
			continue
		var colour: Color = kit[group_name]
		colour.a = 1.0
		if readable.call(colour):
			return colour
	return from_seed(seed_value)


## A stable palette colour for a golfer, so the same golfer keeps the same
## colour between visits and two golfers with no kit are not all one colour.
static func from_seed(seed_value: int) -> Color:
	var index := posmod(seed_value, PALETTE.size())
	return PALETTE[index]


## How a favourite colour is named to the player: its hex, the way the game's
## other colour plates read, e.g. "Favourite colour e94f37".
static func describe(colour: Color) -> String:
	return "Favourite colour %s" % to_field(colour)


## The colour as it is written in a card, save or profile. `colour` is the
## golfer's favourite, or null/empty for a golfer that has none yet and should
## be given one from their kit (see from_kit).
static func serialize(colour: Variant) -> String:
	if colour == null:
		return ""
	if colour is String:
		var text := (colour as String).strip_edges()
		return "" if text.is_empty() else to_field(parse(text))
	return to_field(parse(colour))
