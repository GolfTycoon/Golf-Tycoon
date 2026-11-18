extends PanelContainer
class_name VisitorIdentityCard
## The first card of a Visiting Golfer profile: the golfer themselves.
##
## A locker badge rather than a list. The skin snapshot stands in a recessed
## well at the left, twice its native size so the visitor is the largest thing
## on the shelf; their name, tier, membership and whether they are out on the
## course or a past visitor stack beside it, with three round readings along
## the bottom. A Locate chip floats over the portrait's corner for a golfer who
## is still out there - the same overlay the Play Course pros use.
##
## The card is exactly `VisitorProfileStyle.CARD_HEIGHT` tall, like every card
## in the row, so opening a profile never changes the shelf's height.
## `texture` is the same skin snapshot the register's plate drew, kept as a
## property because that is what the rest of the profile row shares.

const WIDTH := 300.0
const WELL_WIDTH := 100.0
const WELL_HEIGHT := 112.0
const TEXT_WIDTH := 176.0

var texture: Texture2D = null
var accent: Color = VisitorProfileStyle.ACTIVE_ACCENT

var _locate: Button


func _init() -> void:
	name = "VisitorIdentityCard"
	custom_minimum_size = Vector2(WIDTH, VisitorProfileStyle.CARD_HEIGHT)
	size_flags_vertical = Control.SIZE_SHRINK_CENTER
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	# Decorative apart from the Locate chip, which still takes its own presses.
	mouse_filter = Control.MOUSE_FILTER_IGNORE


## Fill the card from one visitor's data row (the same dictionary the register
## plate was made from). `locate` is the shared camera chip; the caller owns
## its tooltip and signal, and only an on-course golfer gets one.
func setup(visitor_name: String, data: Dictionary, active: bool,
		locate: Button = null) -> void:
	accent = VisitorProfileStyle.ACTIVE_ACCENT if active else VisitorProfileStyle.PAST_ACCENT
	accessibility_name = "%s, visiting golfer" % visitor_name
	texture = data.get("portrait")
	_locate = locate
	add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(accent,
		MenuStyle.CARD_BG.lerp(accent, 0.07), 0, 0))

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", int(VisitorProfileStyle.CARD_PAD))
	margin.add_theme_constant_override("margin_right", int(VisitorProfileStyle.CARD_PAD))
	margin.add_theme_constant_override("margin_top", int(VisitorProfileStyle.CARD_PAD))
	margin.add_theme_constant_override("margin_bottom", int(VisitorProfileStyle.CARD_PAD))
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)

	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(row)

	row.add_child(_build_well())
	row.add_child(_build_identity(visitor_name, data, active))


## The portrait's recessed well, with the camera chip floating in its corner.
func _build_well() -> Control:
	var well := Control.new()
	well.custom_minimum_size = Vector2(WELL_WIDTH, WELL_HEIGHT)
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var recess := PanelContainer.new()
	recess.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	recess.add_theme_stylebox_override("panel",
		PixelButtonStyle.inset_style(accent, Color("0a1c18"), 2))
	recess.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(recess)

	var portrait := VisitorPortrait.new()
	portrait.texture = texture
	portrait.set_display_size(Vector2(96, 108))
	portrait.show_backdrop = false
	portrait.ground_shadow = true
	recess.add_child(portrait)

	if _locate != null:
		_locate.custom_minimum_size = Vector2(36, 36)
		_locate.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_RIGHT)
		_locate.offset_left = -40
		_locate.offset_top = -40
		_locate.offset_right = -4
		_locate.offset_bottom = -4
		well.add_child(_locate)
	return well


## Name, tier, membership, status and the three round readings.
func _build_identity(visitor_name: String, data: Dictionary, active: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 2)
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_FILL
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var name_label := VisitorProfileStyle.fit_label(visitor_name, 15, 10, TEXT_WIDTH, VisitorProfileStyle.LIT)
	name_label.custom_minimum_size.y = 20
	name_label.tooltip_text = visitor_name
	name_label.mouse_filter = Control.MOUSE_FILTER_PASS
	column.add_child(name_label)

	var tier := GolferTier.get_tier_name(int(data.get("tier", GolferTier.Tier.BEGINNER)))
	var tier_text := tier.to_upper()
	if bool(data.get("owner", false)):
		tier_text = "YOUR GOLFER"
	elif bool(data.get("returning", false)):
		tier_text += "  ·  RETURNING"
	column.add_child(VisitorProfileStyle.width_label(tier_text, 9,
		accent.lightened(0.2), TEXT_WIDTH))

	column.add_child(_build_chip(int(data.get("membership", ClubMembership.Tier.NON_MEMBER))))

	var status := HBoxContainer.new()
	status.custom_minimum_size.y = 14
	status.add_theme_constant_override("separation", 5)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(status)
	status.add_child(VisitorProfileStyle.StatusDot.new(accent))
	status.add_child(VisitorProfileStyle.width_label(
		"ON THE COURSE" if active else "PAST VISITOR", 9, accent.lightened(0.25)))
	var status_detail := VisitorProfileStyle.make_label(_status_detail_text(data, active), 9, VisitorProfileStyle.MUTED)
	status_detail.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	status_detail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.add_child(status_detail)

	var spacer := Control.new()
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(spacer)

	var stats := HBoxContainer.new()
	stats.custom_minimum_size.y = VisitorProfileStyle.TILE_HEIGHT
	stats.add_theme_constant_override("separation", 4)
	stats.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(stats)
	for tile in _round_tiles(data, active):
		stats.add_child(tile)
	return column


## The membership plate: the golfer's tier in that tier's own colour, with the
## green fee they pay written beside it.
func _build_chip(membership: int) -> PanelContainer:
	var color := ClubMembership.tier_color(membership)
	var chip := PanelContainer.new()
	chip.custom_minimum_size.y = 18
	chip.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	chip.add_theme_stylebox_override("panel",
		PixelButtonStyle.card_style(color, PixelButtonStyle.State.NORMAL,
			MenuStyle.CARD_BG, 6, 2, 2))
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(line)
	line.add_child(VisitorProfileStyle.Mark.new(color))

	var text := ClubMembership.tier_name(membership).to_upper()
	if ClubMembership.is_member(membership):
		text += "  ·  %d%% FEE" % int(round(ClubMembership.fee_multiplier(membership) * 100.0))
	else:
		text += "  ·  PUBLIC FEE"
	line.add_child(VisitorProfileStyle.width_label(text, 9, color.lightened(0.25)))
	return chip


## "Hole 8" for a golfer on the course, the round's date for a past visitor.
func _status_detail_text(data: Dictionary, active: bool) -> String:
	if active:
		return "HOLE %d" % int(data.get("hole", 1))
	if data.has("day"):
		return GameCalendar.format_date_short(int(data.get("day", 1))).to_upper()
	return ""


## Three recessed readouts along the card's foot: where the round stands now,
## or how the last one finished.
func _round_tiles(data: Dictionary, active: bool) -> Array[Control]:
	var tiles: Array[Control] = []
	if active:
		var attitude := clampf(float(data.get("attitude", 0.5)), 0.0, 1.0)
		tiles.append(_stat_tile("HOLE", str(int(data.get("hole", 1))), VisitorProfileStyle.CREAM))
		tiles.append(_stat_tile("STROKES", str(int(data.get("strokes", 0))), VisitorProfileStyle.CREAM))
		tiles.append(_stat_tile("ATTITUDE", "%d%%" % int(round(attitude * 100.0)),
			VisitorProfileStyle.level_color(attitude)))
		return tiles

	var strokes := int(data.get("strokes", 0))
	var par := int(data.get("par", 0))
	var to_par := strokes - par
	var to_par_text := "E"
	if to_par > 0:
		to_par_text = "+%d" % to_par
	elif to_par < 0:
		to_par_text = str(to_par)
	tiles.append(_stat_tile("TO PAR", to_par_text, UIConstants.get_score_color(to_par)))
	tiles.append(_stat_tile("STROKES", str(strokes), VisitorProfileStyle.CREAM))
	tiles.append(_stat_tile("PAR", str(par) if par > 0 else "-", VisitorProfileStyle.CREAM))
	return tiles


## One dark readout: a small caption over a large pixel reading.
func _stat_tile(caption: String, value: String, color: Color) -> PanelContainer:
	var tile := PanelContainer.new()
	tile.custom_minimum_size.y = VisitorProfileStyle.TILE_HEIGHT
	tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	tile.add_theme_stylebox_override("panel",
		PixelButtonStyle.inset_style(accent, Color("0a1c18"), 2))
	tile.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	tile.add_child(column)

	var caption_label := VisitorProfileStyle.make_label(caption, 8, VisitorProfileStyle.MUTED)
	caption_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	column.add_child(caption_label)
	var value_label := VisitorProfileStyle.make_label(value, 15, color)
	value_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_label.custom_minimum_size.y = 19
	column.add_child(value_label)
	return tile
