extends VBoxContainer
class_name CourseMapLandPanel
## CourseMapLandPanel - Land Management: the property, parcel by parcel.
##
## The map beside this panel draws the six-by-six parcel grid; this is the
## ledger for it. It shows what the company owns, what is for sale and what each
## parcel costs, and it is where a parcel is actually bought - the same
## LandManager.purchase_parcel() the Land panel in the Maps tab calls, so a
## purchase from either place generates the parcel's terrain (see main.gd).
##
## Picking a parcel on the map selects it here, and picking a row selects it on
## the map: the screen keeps the one selection (see CourseMapScreen.set_selection).

signal parcel_selected(parcel: Vector2i)
signal buy_requested(parcel: Vector2i)

## Rows listed before the rest are summarised: on a phone the panel is a scroll
## away from being unusable otherwise.
const ROW_LIMIT := 7

var compact: bool = false
var _selected: Vector2i = Vector2i(-1, -1)

func _ready() -> void:
	refresh()

## The parcels the panel lists: for sale first (cheapest first), then a summary.
func set_selected(parcel: Vector2i) -> void:
	if parcel == _selected:
		return
	_selected = parcel
	refresh()

func set_compact(value: bool) -> void:
	if compact == value:
		return
	compact = value
	refresh()

func refresh() -> void:
	for child in get_children():
		remove_child(child)
		child.queue_free()
	add_theme_constant_override("separation", 8 if not compact else 6)
	add_child(CourseMapStyle.kicker("Land management", 10))
	add_child(CourseMapStyle.title("The property", 19 if not compact else 17))

	var land: LandManager = GameManager.land_manager
	if land == null:
		add_child(CourseMapStyle.hint("No land on this course yet."))
		return

	add_child(_summary_card(land))
	add_child(_selected_card(land))
	var for_sale := _for_sale(land)
	if for_sale.is_empty():
		add_child(CourseMapStyle.hint("Every parcel around the course is yours. Nothing left to buy here."))
	else:
		add_child(_for_sale_list(land, for_sale))
	add_child(CourseMapStyle.hint(
		"Bought land is yours for good; Premium and Elite parcels arrive with their own terrain (a grove, a pond, a clearing). "
		+ "Tap a parcel on the map to read it."))

# --- Cards -------------------------------------------------------------------

func _summary_card(land: LandManager) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 4)
	var owned: int = land.owned_parcels.size()
	var total: int = LandManager.PARCEL_GRID_COLS * LandManager.PARCEL_GRID_ROWS
	var tiles: int = land.get_owned_tile_count()
	body.add_child(CourseMapStyle.label(
		"Owned: %d of %d parcels (%s tiles)" % [owned, total, _grouped(tiles)],
		12 if not compact else 11, CourseMapStyle.TEXT_BRIGHT, CourseMapStyle.SUBTITLE_FONT))
	var for_sale := land.get_purchasable_parcels()
	if for_sale.is_empty():
		body.add_child(CourseMapStyle.label("The whole block is bought.", 11, CourseMapStyle.MINT))
	else:
		var cheapest := _cheapest(land, for_sale)
		body.add_child(CourseMapStyle.label(
			"%d parcels touching your land · cheapest %s" % [for_sale.size(), CourseMapStyle.money(cheapest)],
			11, CourseMapStyle.TEXT_QUIET))
	return CourseMapStyle.framed(body)

func _selected_card(land: LandManager) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 6)
	var parcel := _selected
	if parcel == Vector2i(-1, -1):
		body.add_child(CourseMapStyle.label("No parcel picked", 12, CourseMapStyle.TEXT_SECONDARY,
			CourseMapStyle.SUBTITLE_FONT))
		body.add_child(CourseMapStyle.hint("Tap a parcel on the map — the gold ones are for sale."))
		return CourseMapStyle.framed(body, 10, CourseMapStyle.INSET)

	var tier: int = land.get_parcel_tier(parcel)
	var tier_name := LandManager.get_tier_name(tier)
	body.add_child(CourseMapStyle.label("Parcel %d, %d" % [parcel.x, parcel.y], 13,
		CourseMapStyle.TEXT_BRIGHT, CourseMapStyle.SUBTITLE_FONT))
	var tile_count: int = LandManager.PARCEL_SIZE * LandManager.PARCEL_SIZE
	if land.owned_parcels.has(parcel):
		body.add_child(CourseMapStyle.chip_row([
			{"text": "%s land" % tier_name, "color": _tier_color(tier)},
			{"text": "Owned · %d tiles" % tile_count, "color": CourseMapStyle.MINT},
		]))
		return CourseMapStyle.framed(body, 10, CourseMapStyle.INSET)

	var cost := land.get_parcel_cost(parcel)
	var check := land.can_purchase_parcel(parcel)
	body.add_child(CourseMapStyle.chip_row([
		{"text": "%s land" % tier_name, "color": _tier_color(tier)},
		{"text": "%s · %d tiles" % [CourseMapStyle.money(cost), tile_count], "color": CourseMapStyle.GOLD},
	]))
	var can_buy := bool(check.get("can_buy", false))
	var buy := CourseMapStyle.button("Buy for %s" % CourseMapStyle.short_money(cost), true)
	buy.disabled = not can_buy
	buy.tooltip_text = "Buy this parcel in full" if can_buy else str(check.get("reason", ""))
	buy.pressed.connect(func(): buy_requested.emit(parcel))
	body.add_child(buy)
	if not can_buy:
		body.add_child(CourseMapStyle.hint(str(check.get("reason", ""))))
	return CourseMapStyle.framed(body, 10, CourseMapStyle.INSET)

func _for_sale_list(land: LandManager, for_sale: Array) -> Control:
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 5)
	body.add_child(CourseMapStyle.kicker("For sale", 10))
	for parcel in for_sale.slice(0, ROW_LIMIT):
		body.add_child(_parcel_row(land, parcel))
	if for_sale.size() > ROW_LIMIT:
		body.add_child(CourseMapStyle.hint(
			"%d more parcels touch your land — pan the map to find them." % (for_sale.size() - ROW_LIMIT)))
	return CourseMapStyle.framed(body)

func _parcel_row(land: LandManager, parcel: Vector2i) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)

	var tier: int = land.get_parcel_tier(parcel)
	var cost := land.get_parcel_cost(parcel)
	var picked := parcel == _selected
	var pick := CourseMapStyle.choice("Parcel %d, %d" % [parcel.x, parcel.y], 11)
	pick.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	pick.button_pressed = picked
	pick.tooltip_text = "%s land — tap to show it on the map" % LandManager.get_tier_name(tier)
	pick.pressed.connect(func(): parcel_selected.emit(parcel))
	row.add_child(pick)

	row.add_child(CourseMapStyle.label(CourseMapStyle.short_money(cost), 11,
		_tier_color(tier), CourseMapStyle.SUBTITLE_FONT))

	var check := land.can_purchase_parcel(parcel)
	var buy := CourseMapStyle.icon_button("Buy", CourseMapStyle.MINT, 11)
	buy.disabled = not bool(check.get("can_buy", false))
	buy.tooltip_text = "Buy parcel %d, %d" % [parcel.x, parcel.y] if buy.disabled == false \
		else str(check.get("reason", ""))
	buy.pressed.connect(func(): buy_requested.emit(parcel))
	row.add_child(buy)
	return row

# --- Helpers -----------------------------------------------------------------

func _for_sale(land: LandManager) -> Array:
	var parcels := land.get_purchasable_parcels()
	parcels.sort_custom(func(a, b): return land.get_parcel_cost(a) < land.get_parcel_cost(b))
	return parcels

func _cheapest(land: LandManager, parcels: Array) -> int:
	var best := 0
	for i in parcels.size():
		var cost := land.get_parcel_cost(parcels[i])
		if i == 0 or cost < best:
			best = cost
	return best

static func _tier_color(tier: int) -> Color:
	match tier:
		LandManager.TIER_PREMIUM: return CourseMapStyle.GOLD
		LandManager.TIER_ELITE: return Color("bcd6ee")
		_: return CourseMapStyle.MINT

static func _grouped(amount: int) -> String:
	var digits := str(absi(amount))
	var out := ""
	for i in range(digits.length()):
		if i > 0 and (digits.length() - i) % 3 == 0:
			out += ","
		out += digits[i]
	return out
