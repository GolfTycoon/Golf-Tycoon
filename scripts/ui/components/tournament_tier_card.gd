extends PanelContainer
class_name TournamentTierCard
## One tournament the course can host, as a ticket on the Play Course shelf.
##
## The tiers used to be a run of stat rows in one column of the shelf. Now each
## event is a card of its own, separated from its neighbours by air: every
## ticket wears the frame every other card in the dock wears (the shared ink
## outline, accent rim, gloss and contact shadow from PixelButtonStyle), so it
## sits among the shelf's buttons rather than replacing them, and each carries
## its own prestige colour down the left spine.
##
## A ticket is laid out top to bottom the way a poster for the event would be:
##
##  * the crest: a pixel trophy in the tier's colour, with the tier's rank and
##    the size of the field set beside it. The crest is the one thing on the
##    card that is not type, and it is what the eye lands on first;
##  * the event's name, under it, in the shelf's cream;
##  * the purse, in the palette's gold, with the entry fee quiet against it -
##    the two numbers a host weighs against each other;
##  * a perforated rule, the ticket's fold, then the bar the course must clear
##    and the reputation the event pays;
##  * the Host card, the ticket's one action: gold when the course qualifies, a
##    quiet card when it does not;
##  * the gate line, which says which of the two it is - ready, or what still
##    stands in the way. It keeps its row in both states, so a card never
##    changes height when the treasury or the course moves under it.
##
## The ticket itself is a static frame, not a button: the Host card inside it is
## the only pressable thing, and `host_button` hands it to callers (and tests)
## the way the old tier column's button was handed over.

signal host_pressed(tier: int)

## Width of one ticket. Three of them, their gaps and the desk column beside
## them fill a 1000px window; the fourth runs off the right, which is what the
## shelf's sideways scroll is for.
const CARD_WIDTH := 226.0
## Frame padding, in pixels: the rim's own bands (ink plus accent) and a breath,
## so no word ever touches the frame.
const PAD := 8
## The Host card's height, and the crest's side.
const HOST_HEIGHT := 30.0
const CREST := 30.0
## Width of the ticket's coloured spine.
const SPINE_WIDTH := 3.0

const KICKER_FONT_SIZE := 10
const NAME_FONT_SIZE := 13
const PURSE_FONT_SIZE := 15
const SMALL_FONT_SIZE := 11
const TINY_FONT_SIZE := 10
## Row separation inside the ticket: tight enough that every row fits the
## bottom bar, open enough that the poster keeps its rhythm.
const ROW_GAP := 2

const FONT: Font = PixelCircleButton.FONT
const CREAM := PixelCircleButton.CREAM
const GOLD := Color("e5c57d")
const QUIET := Color("93a89a")
const BAR_TEXT := Color("cfdccb")

## One prestige colour per tier, low to high: fairway green, sky blue, flag
## gold, then the champion's orchid. They are the ladder the player climbs, so
## the four tickets read in rank order before a word of them is read.
const TIER_ACCENTS := [
	Color("8fd3a3"), Color("79b7e2"), Color("e8c576"), Color("c79ade"),
]
const TIER_RANKS := ["TIER I", "TIER II", "TIER III", "TIER IV"]

var tier := 0
## The tier's data as TournamentSystem reports it, mods' patches included.
var data: Dictionary = {}
var accent := Color.WHITE
var host_button: Button = null

## The nodes a refresh writes to. Built once; afterwards a refresh only rewrites
## their text and the Host card's state, so the shelf never churns focus by
## rebuilding itself while the treasury ticks over.
var _crest: TextureRect = null
var _kicker: Label = null
var _name: Label = null
var _purse: Label = null
var _entry: Label = null
var _bar: Label = null
var _reward: Label = null
var _gate: Label = null
var _rule: ColorRect = null
var _available := false


## Build the ticket for the `tier_index`th tier of TournamentSystem, whose enum
## value is `tier_value`, described by `tier_data`.
func configure(tier_index: int, tier_value: int, tier_data: Dictionary) -> void:
	tier = tier_value
	data = tier_data
	accent = TIER_ACCENTS[clampi(tier_index, 0, TIER_ACCENTS.size() - 1)]
	name = "TournamentCard%d" % tier_index
	custom_minimum_size = Vector2(CARD_WIDTH, 0)
	size_flags_vertical = Control.SIZE_FILL
	mouse_filter = Control.MOUSE_FILTER_PASS
	if _name == null:
		_build()
	_refresh_texts()
	_refresh_frame()


func _build() -> void:
	# The ticket's rows are one plain column laid inside its frame: no scroll
	# view and no second card, so the shelf stays the only thing that scrolls.
	var body := VBoxContainer.new()
	body.name = "TicketBody"
	body.add_theme_constant_override("separation", ROW_GAP)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(body)

	# Crest row: the trophy stands in the tier's colour, with the rank and the
	# size of the field beside it. A 16x16 sprite at 2x is the same crisp block
	# art the dock's medallions draw, so the crest belongs to that set.
	var crest_row := HBoxContainer.new()
	crest_row.name = "CrestRow"
	crest_row.add_theme_constant_override("separation", 6)
	body.add_child(crest_row)
	var well := PanelContainer.new()
	well.name = "CrestWell"
	well.custom_minimum_size = Vector2(CREST + 8.0, CREST + 8.0)
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", PixelButtonStyle.inset_style(
			Color(accent.r, accent.g, accent.b, 0.55), MenuStyle.INSET_BG, 2))
	crest_row.add_child(well)
	_crest = TextureRect.new()
	_crest.name = "Crest"
	_crest.custom_minimum_size = Vector2(CREST, CREST)
	_crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_crest.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_crest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(_crest)
	# The rank and the event's name stack beside the crest, so the ticket's
	# header is one block: what this is, in which tier, with how many golfers.
	var crest_text := VBoxContainer.new()
	crest_text.name = "CrestText"
	crest_text.add_theme_constant_override("separation", 0)
	crest_text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crest_text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	crest_row.add_child(crest_text)
	_kicker = ellipsize(_make_label(KICKER_FONT_SIZE, QUIET, HORIZONTAL_ALIGNMENT_LEFT))
	_kicker.name = "TierRank"
	crest_text.add_child(_kicker)
	_name = ellipsize(_make_label(NAME_FONT_SIZE, CREAM, HORIZONTAL_ALIGNMENT_LEFT))
	_name.name = "TierName"
	crest_text.add_child(_name)

	# Purse row: the money the event pays in the palette's gold, with the entry
	# fee quiet against it - the investment beside the return.
	var purse_row := HBoxContainer.new()
	purse_row.name = "PurseRow"
	purse_row.add_theme_constant_override("separation", 4)
	body.add_child(purse_row)
	var purse_caption := _make_label(TINY_FONT_SIZE, QUIET, HORIZONTAL_ALIGNMENT_LEFT)
	purse_caption.name = "PurseCaption"
	purse_caption.text = "PURSE"
	purse_caption.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	purse_row.add_child(purse_caption)
	_purse = ellipsize(_make_label(PURSE_FONT_SIZE, GOLD, HORIZONTAL_ALIGNMENT_LEFT))
	_purse.name = "Purse"
	_purse.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	purse_row.add_child(_purse)
	_entry = _make_label(TINY_FONT_SIZE, QUIET, HORIZONTAL_ALIGNMENT_RIGHT)
	_entry.name = "EntryFee"
	_entry.size_flags_horizontal = Control.SIZE_SHRINK_END
	_entry.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	purse_row.add_child(_entry)

	# The perforation: the ticket's fold between what it pays and what it asks.
	# A plain node, so it lines up identically on all four tickets.
	_rule = ColorRect.new()
	_rule.name = "Perforation"
	_rule.custom_minimum_size = Vector2(0, 1)
	_rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_rule)

	# The bar row: what the course must clear on the left, what the event pays
	# in reputation on the right.
	var bar_row := HBoxContainer.new()
	bar_row.name = "QualifyingRow"
	bar_row.add_theme_constant_override("separation", 4)
	body.add_child(bar_row)
	_bar = ellipsize(_make_label(SMALL_FONT_SIZE, BAR_TEXT, HORIZONTAL_ALIGNMENT_LEFT))
	_bar.name = "QualifyingBar"
	_bar.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	bar_row.add_child(_bar)
	_reward = _make_label(TINY_FONT_SIZE, QUIET, HORIZONTAL_ALIGNMENT_RIGHT)
	_reward.name = "ReputationReward"
	_reward.size_flags_horizontal = Control.SIZE_SHRINK_END
	_reward.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	bar_row.add_child(_reward)

	# Everything above settles at the top; the action block sits on the
	# ticket's bottom edge, so four tickets wear their Host cards along one
	# line however long their event names are.
	var spacer := Control.new()
	spacer.name = "TicketSpacer"
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)

	host_button = Button.new()
	host_button.name = "HostButton"
	host_button.text = "Host Tournament"
	host_button.custom_minimum_size = Vector2(0, HOST_HEIGHT)
	host_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	host_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	host_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	host_button.focus_mode = Control.FOCUS_ALL
	host_button.add_theme_font_override("font", FONT)
	host_button.add_theme_font_size_override("font_size", SMALL_FONT_SIZE)
	host_button.pressed.connect(func() -> void: host_pressed.emit(tier))
	body.add_child(host_button)

	_gate = ellipsize(_make_label(TINY_FONT_SIZE, QUIET, HORIZONTAL_ALIGNMENT_CENTER))
	_gate.name = "GateLine"
	body.add_child(_gate)

	resized.connect(queue_redraw)


## Trim a label with an ellipsis when its text outgrows its space. Only the
## labels that stretch (the event name, the purse, the course bar) want this:
## the others are short, fixed strings and must keep their own minimum width.
static func ellipsize(label: Label) -> Label:
	label.clip_text = true
	label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	return label


func _make_label(font_size: int, color: Color, align: HorizontalAlignment) -> Label:
	var label := Label.new()
	label.add_theme_font_override("font", FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.horizontal_alignment = align
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# No overrun by default: a label carrying trimming reports a one-pixel
	# minimum, and the short figures at the right of a row would then collapse
	# instead of claiming their own width. `ellipsize` opts one in.
	return label


## The tier's fixed facts: nothing here changes while the game runs.
func _refresh_texts() -> void:
	var rank: String = TIER_RANKS[clampi(tier, 0, TIER_RANKS.size() - 1)]
	var field := int(data.get("participant_count", 0))
	_kicker.text = rank if field <= 0 else "%s · %d GOLFERS" % [rank, field]
	_name.text = str(data.get("name", "Tournament"))
	_purse.text = MenuScreenKit.format_money(int(data.get("prize_pool", 0)))
	_entry.text = "%s ENTRY" % MenuScreenKit.format_money(int(data.get("entry_cost", 0)))
	_bar.text = "%d+ HOLES · %.1f STARS" % [int(data.get("min_holes", 0)),
			float(data.get("min_rating", 0.0))]
	var reputation := int(data.get("reputation_reward", 0))
	_reward.text = "+%d REP" % reputation
	_reward.visible = reputation > 0
	_crest.texture = PixelIcon.texture(PixelIcon.Kind.TROPHY, int(CREST), accent)
	_rule.color = Color(accent.r, accent.g, accent.b, 0.30)


## Write the ticket's one changing half: whether it can be hosted right now and
## the line that says why (or why not). `can_schedule` is a TournamentManager
## result: {can_schedule, reason}.
##
## `cooldown_days` is the course's own rest between events. That wait is the same
## for every ticket, so it is told once at the desk and each ticket simply opens
## its gate on the same day: a shelf of tickets counting down together reads as a
## schedule, while the same reason written four times reads as a greyed-out wall.
func set_availability(can_schedule: Dictionary, cooldown_days: int = 0) -> void:
	_available = bool(can_schedule.get("can_schedule", false))
	var reason := str(can_schedule.get("reason", "")).strip_edges()
	host_button.disabled = not _available
	host_button.text = "Host Tournament" if _available else "Locked"
	host_button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND if _available \
			else Control.CURSOR_ARROW
	if _available:
		var gate := int(data.get("spectator_revenue", 0))
		var sponsors := int(data.get("sponsorship_revenue", 0))
		host_button.tooltip_text = "Starts right away — you are in the field"
		_gate.text = "%s GATE · %s SPONSORS" % [
				MenuScreenKit.format_money_compact(gate),
				MenuScreenKit.format_money_compact(sponsors)]
		_gate.tooltip_text = "What the course keeps beyond the purse: %s in gate takings and %s in sponsorship." % [
				MenuScreenKit.format_money(gate), MenuScreenKit.format_money(sponsors)]
		_gate.add_theme_color_override("font_color", accent)
	elif cooldown_days > 0:
		host_button.tooltip_text = "The course is resting between events — %d days until the next one can be hosted" % cooldown_days
		_gate.text = "OPENS IN %d DAYS" % cooldown_days
		_gate.add_theme_color_override("font_color", Color("d8a08c"))
	else:
		host_button.tooltip_text = reason if not reason.is_empty() \
				else "The course does not qualify yet"
		_gate.text = reason.to_upper() if not reason.is_empty() else "COURSE NOT READY"
		_gate.add_theme_color_override("font_color", Color("d8a08c"))
	if not _available:
		_gate.tooltip_text = _gate.text
	host_button.accessibility_name = "Host %s" % str(data.get("name", "tournament"))
	host_button.accessibility_description = host_button.tooltip_text
	# A ticket whose event cannot run yet keeps its silhouette but dims its
	# crest, so a shelved event reads as waiting rather than broken.
	var well := get_node_or_null("TicketBody/CrestRow/CrestWell") as Control
	if well != null:
		well.modulate = Color.WHITE if _available else Color(1, 1, 1, 0.6)
	_refresh_frame()


## Paint the frame and the Host card: a full-strength rim, a lit spine and the
## gold call to action when the course qualifies; the same shape with a muted
## rim and a quiet card when it does not. The Host card's own styles carry no
## content margins, so its height is exactly HOST_HEIGHT on both faces.
func _refresh_frame() -> void:
	var rim := accent if _available else accent.lerp(Color("5c6b61"), 0.55)
	add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
			rim, MenuStyle.CARD_BG, PAD, PAD))
	var card_accent := GOLD if _available else Color("8fa396")
	host_button.add_theme_stylebox_override("normal", PixelButtonStyle.card_style(
			card_accent, PixelButtonStyle.State.NORMAL, MenuStyle.CARD_BG, 6, 0, 0))
	host_button.add_theme_stylebox_override("hover", PixelButtonStyle.card_style(
			card_accent, PixelButtonStyle.State.HOVER, MenuStyle.CARD_BG_HOVER, 6, 0, 0))
	host_button.add_theme_stylebox_override("pressed", PixelButtonStyle.card_style(
			card_accent.darkened(0.2), PixelButtonStyle.State.PRESSED,
			MenuStyle.CARD_BG_PRESSED, 6, 0, 0))
	host_button.add_theme_stylebox_override("disabled", PixelButtonStyle.card_style(
			Color("7d8f84"), PixelButtonStyle.State.DISABLED,
			MenuStyle.CARD_BG_DISABLED, 6, 0, 0))
	# The focus wash keeps the same padding as the resting card, so a keyboard
	# player's selection never moves the caption inside it.
	PixelButtonStyle.paint_focus(host_button, card_accent, 6, 0, 0)
	for state in ["font_color", "font_hover_color"]:
		host_button.add_theme_color_override(state, GOLD if _available else QUIET)
	host_button.add_theme_color_override("font_pressed_color", MenuStyle.INK)
	host_button.add_theme_color_override("font_focus_color", MenuStyle.INK)
	host_button.add_theme_color_override("font_disabled_color", UIConstants.COLOR_TEXT_MUTED)
	# The fold's bites are placed from the perforation's global row, which only
	# exists once the ticket has been laid out, so repaint on the way in too.
	queue_redraw()
	call_deferred("queue_redraw")


## The crest's painted sprite, for callers that want the same trophy.
func crest_texture() -> Texture2D:
	return _crest.texture if _crest != null else null


## The ticket's spine, folds and corner ticks. Children paint over this, so the
## spine can run the frame's inner height without ever touching a word.
func _draw() -> void:
	if size.x <= 0.0 or size.y <= 0.0:
		return
	var lift := 0.85 if _available else 0.35
	var spine := Color(accent.r, accent.g, accent.b, lift)
	# The spine stops inside the rim's corner curve, so it reads as inlay in
	# the ticket rather than a stripe pasted over the frame.
	var top := PAD
	var bottom := maxf(size.y - PAD, top)
	draw_rect(Rect2(3, top, SPINE_WIDTH, bottom - top), spine)
	# A pixel notch at each end of the spine: the ticket's staple.
	var notch := Color(PixelButtonStyle.INK.r, PixelButtonStyle.INK.g,
			PixelButtonStyle.INK.b, 0.55)
	draw_rect(Rect2(3, top - 3.0, SPINE_WIDTH, 2), notch)
	draw_rect(Rect2(3, bottom + 1.0, SPINE_WIDTH, 2), notch)
	# The perforation's own mark: a half-round bite out of each frame edge at
	# the fold, drawn in the shelf's ink so the ticket reads as torn along it.
	if _rule != null and _rule.size.x > 0.0:
		var fold := _rule.get_global_rect().position.y - get_global_rect().position.y \
				+ _rule.size.y * 0.5
		var bite := Color(PixelButtonStyle.INK.r, PixelButtonStyle.INK.g,
				PixelButtonStyle.INK.b, 0.85)
		for x in [0.0, size.x - 2.0]:
			draw_rect(Rect2(x, fold - 1.0, 2, 3), bite)
	# Corner ticks in the bottom-right: the same three-pixel mark the dock's
	# plates carry, tying the ticket to the rest of the shelf.
	var tick := Color(accent.r, accent.g, accent.b, 0.55 if _available else 0.25)
	var x := size.x - PAD - 2.0
	var y := size.y - PAD - 3.0
	for i in 3:
		draw_rect(Rect2(x - i * 4.0, y, 2, 2), tick)
