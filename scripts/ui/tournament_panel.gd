extends CenteredPanel
class_name TournamentPanel
## TournamentPanel - UI for viewing and hosting tournaments

signal close_requested
signal play_again_requested
signal tournament_setup_requested
signal main_menu_requested

var embedded := false
var _tournament_manager: TournamentManager = null
var _content_vbox: BoxContainer = null
var _status_label: Label = null
var _status_column: VBoxContainer = null
var _title_label: Label = null
## Host buttons by tier, so a refresh can find and re-enable the exact one the
## player is hovering instead of rebuilding blind.
var _host_buttons: Dictionary = {}

## The Host button for a tier (null when that tier is not on the shelf).
func get_host_button(tier: int) -> Button:
	return _host_buttons.get(tier)

## The "Play It Out" shortcut, for tests and for anything that needs to reach it
## while a round is live (null between events).
var _settle_button: Button

func get_settle_button() -> Button:
	return _settle_button

func _ready() -> void:
	super._ready()
	if embedded:
		size_flags_vertical = Control.SIZE_EXPAND_FILL
		show()
	# Connect to tournament events
	EventBus.tournament_scheduled.connect(_on_tournament_scheduled)
	EventBus.tournament_started.connect(_on_tournament_started)
	EventBus.tournament_completed.connect(_on_tournament_completed)
	# The Host buttons read the course and the treasury, so anything that changes
	# either has to re-enable them. Without this the panel keeps showing a gate
	# computed before the course existed (e.g. a stale "No course data").
	EventBus.new_game_started.connect(_on_course_state_changed)
	EventBus.load_completed.connect(_on_course_state_changed)
	EventBus.hole_created.connect(_on_course_state_changed)
	EventBus.hole_deleted.connect(_on_course_state_changed)
	EventBus.hole_toggled.connect(_on_course_state_changed)
	EventBus.money_changed.connect(_on_course_state_changed)
	EventBus.day_changed.connect(_on_course_state_changed)

func _exit_tree() -> void:
	if EventBus.tournament_scheduled.is_connected(_on_tournament_scheduled):
		EventBus.tournament_scheduled.disconnect(_on_tournament_scheduled)
	if EventBus.tournament_started.is_connected(_on_tournament_started):
		EventBus.tournament_started.disconnect(_on_tournament_started)
	if EventBus.tournament_completed.is_connected(_on_tournament_completed):
		EventBus.tournament_completed.disconnect(_on_tournament_completed)
	for handler in [_on_course_state_changed]:
		for signal_ref in [EventBus.new_game_started, EventBus.load_completed,
				EventBus.hole_created, EventBus.hole_deleted, EventBus.hole_toggled,
				EventBus.money_changed, EventBus.day_changed]:
			if signal_ref.is_connected(handler):
				signal_ref.disconnect(handler)

## Course/economy signals fire often (money changes with every green fee), so a
## change only marks the shelf dirty and the rebuild happens at most a couple of
## times a second, and only while the panel is actually on screen.
var _refresh_pending := false
var _refresh_cooldown := 0.0
const REFRESH_INTERVAL := 0.5

## Marks the shelf stale. Deliberately does not need an exact argument list: it is
## wired to signals carrying anywhere from nil to three values.
func _on_course_state_changed(_a = null, _b = null, _c = null) -> void:
	_refresh_pending = true

func _process(delta: float) -> void:
	if _refresh_cooldown > 0.0:
		_refresh_cooldown -= delta
		return
	if not _refresh_pending or not is_visible_in_tree():
		return
	_refresh_pending = false
	_refresh_cooldown = REFRESH_INTERVAL
	_refresh_display()

func _build_ui() -> void:
	if embedded:
		_build_embedded_ui()
		return
	custom_minimum_size = Vector2(340, 480)

	var margin = MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	add_child(margin)

	var main_vbox = VBoxContainer.new()
	main_vbox.add_theme_constant_override("separation", 8)
	margin.add_child(main_vbox)

	# Title row with close button
	var title_row = HBoxContainer.new()
	main_vbox.add_child(title_row)

	_title_label = Label.new()
	_title_label.text = "Tournaments"
	_title_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_LG)
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title_row.add_child(_title_label)

	var close_btn = Button.new()
	close_btn.text = "X"
	close_btn.custom_minimum_size = Vector2(30, 30)
	close_btn.pressed.connect(_on_close_pressed)
	title_row.add_child(close_btn)

	main_vbox.add_child(HSeparator.new())

	# Status label
	_status_label = Label.new()
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	main_vbox.add_child(_status_label)

	main_vbox.add_child(HSeparator.new())

	# Scrollable content area
	var scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.custom_minimum_size = Vector2(0, 350)
	main_vbox.add_child(scroll)

	_content_vbox = VBoxContainer.new()
	_content_vbox.add_theme_constant_override("separation", 6)
	_content_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(_content_vbox)

## Embedded tournaments are a column of separated tickets on the Player shelf,
## not the standalone dialog's tall list or a nested vertical scrollbar. The
## column leads with the tournament desk's masthead and carries the status line
## under it, so the shelf reads as one section: heading, note from the desk, then
## one card per event. The cards run to the right of that column, each its own
## frame (see TournamentTierCard), and the whole shelf still scrolls sideways.
func _build_embedded_ui() -> void:
	add_theme_font_size_override("font_size", 12)
	# No frame of its own: the shelf's own fairway shows through behind it, so
	# the panel sits in the bottom bar rather than becoming a card inside it.
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var margin := MarginContainer.new()
	for edge in ["left", "right"]:
		margin.add_theme_constant_override("margin_" + edge, 4)
	margin.add_theme_constant_override("margin_top", 0)
	margin.add_theme_constant_override("margin_bottom", 0)
	add_child(margin)
	var shelf := HBoxContainer.new()
	shelf.add_theme_constant_override("separation", 10)
	margin.add_child(shelf)
	_status_column = _build_desk_column(shelf)
	_content_vbox = HBoxContainer.new()
	_content_vbox.name = "TournamentCards"
	_content_vbox.add_theme_constant_override("separation", 10)
	_content_vbox.size_flags_vertical = Control.SIZE_EXPAND_FILL
	shelf.add_child(_content_vbox)

## The masthead column: the desk's crest and name over a rule, then the line
## that says what is happening at the desk - a cooldown, a live event, a result.
## It leads the shelf, so the tickets beside it read as its offering; the title
## is permanent (the shelf would otherwise have no name at all when there is
## nothing to report) and only the note under the rule comes and goes.
func _build_desk_column(shelf: HBoxContainer) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "TournamentDesk"
	column.custom_minimum_size.x = 148.0
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 1)
	shelf.add_child(column)
	# A crest in the Golfers section's own green, so the desk belongs to the
	# same dock the cards beside it come from.
	var accent: Color = TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.GOLFERS]
	var crest_row := HBoxContainer.new()
	crest_row.add_theme_constant_override("separation", 5)
	crest_row.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	column.add_child(crest_row)
	var crest := TextureRect.new()
	crest.name = "TournamentDeskCrest"
	crest.texture = PixelIcon.texture(PixelIcon.Kind.TROPHY, 32, accent)
	crest.custom_minimum_size = Vector2(32, 32)
	crest.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	crest_row.add_child(crest)
	var title := Label.new()
	title.name = "TournamentDeskTitle"
	title.text = "TOURNAMENTS"
	title.add_theme_font_override("font", PixelCircleButton.FONT)
	title.add_theme_font_size_override("font_size", 15)
	title.add_theme_color_override("font_color", PixelCircleButton.CREAM)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	crest_row.add_child(title)
	var rule := ColorRect.new()
	rule.name = "TournamentDeskRule"
	rule.custom_minimum_size = Vector2(0, 1)
	rule.color = Color(accent.r, accent.g, accent.b, 0.45)
	rule.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(rule)
	_status_label = Label.new()
	_status_label.name = "TournamentStatus"
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.add_theme_font_override("font", PixelCircleButton.FONT)
	_status_label.add_theme_font_size_override("font_size", 11)
	_status_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)
	column.add_child(_status_label)
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(spacer)
	return column


func setup(tournament_manager: TournamentManager) -> void:
	_tournament_manager = tournament_manager
	_refresh_display()

func toggle() -> void:
	if visible:
		hide()
	else:
		_refresh_display()
		show_centered()

func _refresh_display() -> void:
	if not _tournament_manager:
		return

	# Clear content
	_host_buttons.clear()
	_settle_button = null
	for child in _content_vbox.get_children():
		_content_vbox.remove_child(child)
		child.queue_free()

	# Check current tournament status
	var info = _tournament_manager.get_tournament_info()
	if info.is_empty():
		_show_available_tournaments()
	else:
		_show_current_tournament(info)
	# An empty status line shouldn't reserve space. On the shelf the desk's
	# masthead stays (it names the section); only its note goes.
	_status_label.visible = _status_label.text != ""

func _show_available_tournaments() -> void:
	if GameManager.is_tournament_mode:
		_show_standalone_post_tournament()
		return

	var cooldown = _tournament_manager.get_cooldown_remaining()
	if cooldown > 0:
		# Kept short: the desk column is a masthead, and the tickets beside it
		# already spell the wait out in their own gate lines.
		_status_label.text = "Cooldown: %d days until next tournament" % cooldown
		_status_label.add_theme_color_override("font_color", UIConstants.COLOR_WARNING_DIM)
	elif embedded:
		# The desk's one line of instruction while the shelf is idle: the tickets
		# say what each event is, this says what the section is for.
		_status_label.text = "Choose an event to host"
		_status_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
	else:
		# Nothing to report: the tier rows speak for themselves.
		_status_label.text = ""
		_status_label.remove_theme_color_override("font_color")

	# While the course is resting between events nothing can be hosted. The
	# standalone dialog skips the four identical "must wait" rows; the shelf
	# keeps its tickets, each opening on the same day, with the wait told once
	# at the desk - so the section reads as a schedule and never empties.
	if cooldown > 0 and not embedded:
		return

	# Show all tournament tiers
	if embedded:
		_build_tier_cards()
	else:
		_build_dialog_tier_rows()

## One separated card per tier on the embedded shelf. The standalone dialog
## keeps its stat rows (see _build_dialog_tier_rows) - a floating dialog has
## the vertical room for a list, while the shelf wants four posters.
func _build_tier_cards() -> void:
	var cooldown := _tournament_manager.get_cooldown_remaining()
	for tier in TournamentSystem.TournamentTier.values():
		var tier_data = TournamentSystem.get_tier_data(tier)
		var can_schedule = _tournament_manager.can_schedule_tournament(tier)
		var card := TournamentTierCard.new()
		card.configure(int(tier), int(tier), tier_data)
		card.set_availability(can_schedule, cooldown)
		card.host_pressed.connect(_on_host_pressed)
		_content_vbox.add_child(card)
		_host_buttons[tier] = card.host_button

## The standalone dialog's tier list: the same facts as the shelf's cards,
## written as rows inside the one scrolling column the dialog already has.
func _build_dialog_tier_rows() -> void:
	for tier in TournamentSystem.TournamentTier.values():
		var tier_data = TournamentSystem.get_tier_data(tier)
		var can_schedule = _tournament_manager.can_schedule_tournament(tier)
		var card: BoxContainer = _content_vbox

		# Tournament name
		var name_label = Label.new()
		name_label.text = tier_data.name
		name_label.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
		card.add_child(name_label)

		# Requirements row
		var req_row = _create_stat_row(
			"Requirements:",
			"%d holes, %.1f stars" % [tier_data.min_holes, tier_data.min_rating],
			UIConstants.COLOR_TEXT_DIM
		)
		card.add_child(req_row)

		# Cost/Prize row
		var cost_row = _create_stat_row(
			"Entry / Prize:",
			"$%d / $%d" % [tier_data.entry_cost, tier_data.prize_pool],
			UIConstants.COLOR_SUCCESS_DIM
		)
		card.add_child(cost_row)

		# Reward row
		var reward_row = _create_stat_row(
			"Reputation:",
			"+%d" % tier_data.reputation_reward,
			UIConstants.COLOR_INFO_DIM
		)
		card.add_child(reward_row)

		# Host button
		var btn_container = HBoxContainer.new()
		btn_container.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.add_child(btn_container)

		var spacer = Control.new()
		spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn_container.add_child(spacer)

		var host_btn = Button.new()
		host_btn.text = "Host Tournament"
		host_btn.custom_minimum_size = Vector2(140, 32)
		host_btn.disabled = not can_schedule.can_schedule
		if can_schedule.can_schedule:
			host_btn.pressed.connect(_on_host_pressed.bind(tier))
			host_btn.tooltip_text = "Starts right away — you are in the field"
		else:
			host_btn.tooltip_text = can_schedule.reason
		btn_container.add_child(host_btn)
		_host_buttons[tier] = host_btn

		card.add_child(HSeparator.new())

func _show_current_tournament(info: Dictionary) -> void:
	var state_text = ""
	match info.state:
		TournamentSystem.TournamentState.SCHEDULED:
			state_text = "Scheduled"
			_status_label.add_theme_color_override("font_color", UIConstants.COLOR_WARNING_DIM)
		TournamentSystem.TournamentState.IN_PROGRESS:
			state_text = "In progress · Round %d of %d" % [info.current_round, info.total_rounds]
			_status_label.add_theme_color_override("font_color", UIConstants.COLOR_SUCCESS)

	_status_label.text = "%s\n%s" % [info.name, state_text]

	if embedded:
		_build_live_event_cards(info)
		return

	var card: BoxContainer = _content_vbox

	# Show tournament info
	var info_label = Label.new()
	info_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	info_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_DIM)

	if info.state == TournamentSystem.TournamentState.IN_PROGRESS:
		var fmt_name := str(info.get("format_name", "Stroke Play"))
		var field_sz := int(info.get("field_size", 0))
		info_label.text = "%s · %d golfers in field." % [fmt_name, field_sz] if field_sz > 0 else "You are in the field: two competitors per hole."
		card.add_child(info_label)

		# The owner is in the field, so the shelf carries their own scoreline.
		var standing = _tournament_manager.get_player_standing()
		if not standing.is_empty():
			var diff: int = standing.score_to_par
			var fmt_type := int(standing.get("format_type", TournamentLibrary.FormatType.STROKE_PLAY))
			var fmt_pts := int(standing.get("format_points", 0))
			var score_str := TournamentLibrary.format_score_for_format(fmt_type, diff, fmt_pts, true)
			var you_label = Label.new()
			you_label.text = "You: %s · rank %d of %d · %d holes in (round %d)" % [
				score_str,
				standing.rank, standing.field_size, standing.holes_completed, standing.round
			]
			if standing.missed_cut:
				you_label.text += " — missed cut"
			you_label.add_theme_font_size_override("font_size", 12)
			you_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)
			card.add_child(you_label)

		# The round being played is the player's own game, but the rest of the event
		# is bookkeeping nobody wants to watch at 8x, so the shelf carries the
		# shortcut to the results.
		var action_row := HBoxContainer.new()
		var settle_btn := Button.new()
		settle_btn.text = "Play It Out"
		settle_btn.custom_minimum_size = Vector2(0, 28)
		settle_btn.tooltip_text = "Settle the rest of the event from the cards as they stand"
		settle_btn.pressed.connect(_on_play_it_out_pressed)
		action_row.add_child(settle_btn)
		_settle_button = settle_btn
		var hint_label := Label.new()
		hint_label.text = " · live board top left"
		hint_label.add_theme_font_size_override("font_size", 11)
		hint_label.add_theme_color_override("font_color", UIConstants.COLOR_TEXT_MUTED)
		action_row.add_child(hint_label)
		card.add_child(action_row)
	else:
		info_label.text = "Tournament about to start. Professional golfers will compete on your course — you with them."
		card.add_child(info_label)

	# Show last results if available
	if not _tournament_manager.tournament_results.is_empty():
		card.add_child(HSeparator.new())

		var results_title = Label.new()
		results_title.text = "Previous Tournament Results"
		results_title.add_theme_font_size_override("font_size", UIConstants.FONT_SIZE_BASE)
		card.add_child(results_title)

		var results = _tournament_manager.tournament_results
		var winner_row = _create_stat_row("Winner:", results.get("winner_name", "Unknown"), UIConstants.COLOR_GOLD)
		card.add_child(winner_row)

		var score_row = _create_stat_row("Score:", "%d (Par %d)" % [results.get("winning_score", 0), results.get("par", 72)], Color.WHITE)
		card.add_child(score_row)

## The shelf's view of a running event, in the same ticket language as the
## hostable tiers: a board card for the event itself (name, state, the owner's
## scoreline and the Play It Out action) and, beside it, the champions' card for
## the last event, when there is one. Both are static frames of the same size as
## a tier ticket; the buttons inside them are the only pressable things.
func _build_live_event_cards(info: Dictionary) -> void:
	var accent: Color = TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.GOLFERS]
	var board := _build_event_card("LiveEventBoard", accent)
	var body: VBoxContainer = board.get_node("TicketBody")
	# The event's own name rides in the crest block, beside the round it is on:
	# the desk note at the head of the shelf already names it, and the board has
	# only the ticket's height to say everything it needs to.
	_add_event_crest(body, PixelIcon.Kind.FLAG, accent, "IN PLAY",
			str(info.get("name", "Tournament")),
			str(info.get("format_name", "Stroke Play")).to_upper(),
			"ROUND %d OF %d" % [int(info.get("current_round", 1)),
					int(info.get("total_rounds", 1))])
	var standing = _tournament_manager.get_player_standing()
	if not standing.is_empty():
		var diff: int = standing.score_to_par
		var fmt_type := int(standing.get("format_type", TournamentLibrary.FormatType.STROKE_PLAY))
		var fmt_pts := int(standing.get("format_points", 0))
		var score_str := TournamentLibrary.format_score_for_format(fmt_type, diff, fmt_pts, true)
		_add_card_label(body, "You: %s" % score_str, 15, UIConstants.COLOR_GOLD)
		_add_card_label(body, "RANK %d OF %d · %d HOLES IN" % [
				standing.rank, standing.field_size, standing.holes_completed], 10,
				UIConstants.COLOR_TEXT_DIM)
		if standing.missed_cut:
			_add_card_label(body, "MISSED CUT", 10, UIConstants.COLOR_DANGER)
	_add_card_spacer(body)
	var settle_btn := _add_card_button(body, "Play It Out", MenuStyle.ACCENT_PRIMARY)
	settle_btn.name = "PlayItOutButton"
	settle_btn.tooltip_text = "Settle the rest of the event from the cards as they stand"
	settle_btn.pressed.connect(_on_play_it_out_pressed)
	_settle_button = settle_btn
	settle_btn.accessibility_description = "Settle the rest of the event. The live board is in the top-left corner."

	if _tournament_manager.tournament_results.is_empty():
		return
	var results := _tournament_manager.tournament_results
	var results_card := _build_event_card("PreviousResultsCard", Color("e5c57d"))
	var results_body: VBoxContainer = results_card.get_node("TicketBody")
	var winner_name := str(results.get("winner_name", "Unknown"))
	if bool(results.get("winner_is_player", false)):
		winner_name += " (you)"
	_add_event_crest(results_body, PixelIcon.Kind.TROPHY, Color("e5c57d"), "LAST CHAMPION",
			winner_name, str(results.get("format_name", "Stroke Play")).to_upper())
	var fmt := int(results.get("format_type", TournamentLibrary.FormatType.STROKE_PLAY))
	var win_str := "%d (Par %d)" % [int(results.get("winning_score", 0)), int(results.get("par", 72))]
	if TournamentLibrary.higher_points_is_better(fmt):
		win_str = TournamentLibrary.format_score_for_format(
				fmt, 0, int(results.get("winning_points", 0)), true)
	_add_card_spacer(results_body)
	_add_card_label(results_body, "WINNING SCORE  %s" % win_str, 12, PixelCircleButton.CREAM)
	if int(results.get("playoff_holes", 0)) > 0:
		_add_card_label(results_body, "WON IN A PLAYOFF", 10, UIConstants.COLOR_GOLD)

## An event card's crest row: the trophy or flag in its recessed well, with the
## card's kicker and its one line of context stacked beside it - the same header
## a tier ticket wears, so the rows read as one set.
func _add_event_crest(body: VBoxContainer, kind: int, accent: Color, kicker: String,
		title: String, context: String = "", detail: String = "") -> void:
	var row := HBoxContainer.new()
	row.name = "CrestRow"
	row.add_theme_constant_override("separation", 6)
	body.add_child(row)
	var well := PanelContainer.new()
	well.name = "CrestWell"
	well.custom_minimum_size = Vector2(TournamentTierCard.CREST + 8.0,
			TournamentTierCard.CREST + 8.0)
	well.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	well.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_theme_stylebox_override("panel", PixelButtonStyle.inset_style(
			Color(accent.r, accent.g, accent.b, 0.55), MenuStyle.INSET_BG, 2))
	row.add_child(well)
	var crest := TextureRect.new()
	crest.name = "Crest"
	crest.texture = PixelIcon.texture(kind, int(TournamentTierCard.CREST), accent)
	crest.custom_minimum_size = Vector2(TournamentTierCard.CREST, TournamentTierCard.CREST)
	crest.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	crest.mouse_filter = Control.MOUSE_FILTER_IGNORE
	well.add_child(crest)
	var text := VBoxContainer.new()
	text.name = "CrestText"
	text.add_theme_constant_override("separation", 0)
	text.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(text)
	_add_card_label(text, kicker, 10, UIConstants.COLOR_TEXT_MUTED)
	_add_card_label(text, title.to_upper() if context.is_empty() else title, 14,
			PixelCircleButton.CREAM)
	if not context.is_empty():
		var line := context if detail.is_empty() else "%s · %s" % [context, detail]
		_add_card_label(text, line.to_upper(), 10, UIConstants.COLOR_TEXT_DIM)

## One of the shelf's event cards: the shared ticket frame, with the body its
## caller fills. The frame is the same recipe the tier tickets wear, so the live
## board and the results card stand in the same row as the hostable events.
func _build_event_card(card_name: String, accent: Color) -> PanelContainer:
	var card := PanelContainer.new()
	card.name = card_name
	card.custom_minimum_size = Vector2(TournamentTierCard.CARD_WIDTH, 0)
	card.size_flags_vertical = Control.SIZE_FILL
	card.add_theme_stylebox_override("panel", PixelButtonStyle.panel_style(
			accent, MenuStyle.CARD_BG, TournamentTierCard.PAD, TournamentTierCard.PAD))
	var body := VBoxContainer.new()
	body.name = "TicketBody"
	body.add_theme_constant_override("separation", 1)
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL
	card.add_child(body)
	_content_vbox.add_child(card)
	return card

func _add_card_label(body: VBoxContainer, text: String, font_size: int, color: Color) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", PixelCircleButton.FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	# Trimming costs a label its minimum width (see TournamentTierCard), so
	# event cards only trim the lines that can actually outgrow their row.
	body.add_child(label)
	return label

func _add_card_spacer(body: VBoxContainer) -> void:
	var spacer := Control.new()
	spacer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	spacer.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(spacer)

## The one action on an event card: the shared gold call to action, sized to the
## ticket's own Host cards, with the content margins that keep its height fixed.
func _add_card_button(body: VBoxContainer, text: String, accent: Color) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(0, TournamentTierCard.HOST_HEIGHT)
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	button.focus_mode = Control.FOCUS_ALL
	button.add_theme_font_override("font", PixelCircleButton.FONT)
	button.add_theme_font_size_override("font_size", 11)
	button.add_theme_stylebox_override("normal", PixelButtonStyle.card_style(
			accent, PixelButtonStyle.State.PRIMARY, accent, 6, 0, 0))
	button.add_theme_stylebox_override("hover", PixelButtonStyle.card_style(
			accent.lightened(0.16), PixelButtonStyle.State.PRIMARY,
			accent.lightened(0.14), 6, 0, 0))
	button.add_theme_stylebox_override("pressed", PixelButtonStyle.card_style(
			accent.darkened(0.2), PixelButtonStyle.State.PRESSED,
			accent.darkened(0.12), 6, 0, 0))
	PixelButtonStyle.paint_focus(button, accent, 6, 0, 0)
	for state in ["font_color", "font_hover_color", "font_pressed_color", "font_focus_color"]:
		button.add_theme_color_override(state, MenuStyle.INK)
	body.add_child(button)
	return button

## Standalone Tournament Mode shelf after the event finishes: offer Play Again,
## Tournament Setup, and Main Menu without showing Career hosting costs/gates.
## On the shelf the ended event and the three ways on are two cards, so the row
## keeps the ticket language the rest of the section is drawn in.
func _show_standalone_post_tournament() -> void:
	_status_label.text = "Tournament Complete"
	_status_label.add_theme_color_override("font_color", UIConstants.COLOR_GOLD)

	if embedded:
		_build_post_event_cards()
		return

	var card: BoxContainer = _content_vbox

	if not _tournament_manager.tournament_results.is_empty():
		var results := _tournament_manager.tournament_results
		var w_name := str(results.get("winner_name", "Unknown"))
		if bool(results.get("winner_is_player", false)):
			w_name += " (you)"
		var fmt_type := int(results.get("format_type", TournamentLibrary.FormatType.STROKE_PLAY))
		var fmt_name := str(results.get("format_name", TournamentLibrary.get_format_name(fmt_type)))
		card.add_child(_create_stat_row("Format:", fmt_name, UIConstants.COLOR_INFO_DIM))
		card.add_child(_create_stat_row("Champion:", w_name, UIConstants.COLOR_GOLD))
		var win_str := "%d (Par %d)" % [int(results.get("winning_score", 0)), int(results.get("par", 72))]
		if TournamentLibrary.higher_points_is_better(fmt_type):
			win_str = TournamentLibrary.format_score_for_format(
				fmt_type, 0, int(results.get("winning_points", 0)), true
			)
		if int(results.get("playoff_holes", 0)) > 0:
			win_str += " · Playoff"
		card.add_child(_create_stat_row("Winning Score:", win_str, Color.WHITE))

	var btn_row := HBoxContainer.new()
	btn_row.add_theme_constant_override("separation", 6)
	card.add_child(btn_row)

	var replay_btn := Button.new()
	replay_btn.name = "TournamentPlayAgainButton"
	replay_btn.text = "Play Again"
	replay_btn.custom_minimum_size = Vector2(0, 32)
	replay_btn.pressed.connect(func() -> void: play_again_requested.emit())
	btn_row.add_child(replay_btn)

	var setup_btn := Button.new()
	setup_btn.name = "TournamentSetupButton"
	setup_btn.text = "Tournament Setup"
	setup_btn.custom_minimum_size = Vector2(0, 32)
	setup_btn.pressed.connect(func() -> void: tournament_setup_requested.emit())
	btn_row.add_child(setup_btn)

	var menu_btn := Button.new()
	menu_btn.name = "TournamentMainMenuButton"
	menu_btn.text = "Main Menu"
	menu_btn.custom_minimum_size = Vector2(0, 32)
	menu_btn.pressed.connect(func() -> void: main_menu_requested.emit())
	btn_row.add_child(menu_btn)

## The shelf after a standalone event: the champions' card beside the three
## ways on, in the same frames as the rest of the section. The buttons keep
## their names, so every caller and test finds them where it always did.
func _build_post_event_cards() -> void:
	if not _tournament_manager.tournament_results.is_empty():
		var results := _tournament_manager.tournament_results
		var card := _build_event_card("TournamentResultCard", Color("e5c57d"))
		var body: VBoxContainer = card.get_node("TicketBody")
		var fmt_type := int(results.get("format_type", TournamentLibrary.FormatType.STROKE_PLAY))
		var fmt_name := str(results.get("format_name", TournamentLibrary.get_format_name(fmt_type)))
		_add_event_crest(body, PixelIcon.Kind.TROPHY, Color("e5c57d"), "TOURNAMENT COMPLETE",
				str(results.get("winner_name", "Unknown")),
				fmt_name.to_upper(), "CHAMPION")
		var win_str := "%d (Par %d)" % [int(results.get("winning_score", 0)), int(results.get("par", 72))]
		if TournamentLibrary.higher_points_is_better(fmt_type):
			win_str = TournamentLibrary.format_score_for_format(
					fmt_type, 0, int(results.get("winning_points", 0)), true)
		if int(results.get("playoff_holes", 0)) > 0:
			win_str += " · Playoff"
		_add_card_spacer(body)
		_add_card_label(body, "WINNING SCORE", 10, UIConstants.COLOR_TEXT_MUTED)
		_add_card_label(body, win_str, 14, PixelCircleButton.CREAM)

	var actions := _build_event_card("TournamentActionsCard",
			TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.GOLFERS])
	var actions_body: VBoxContainer = actions.get_node("TicketBody")
	_add_card_label(actions_body, "NEXT", 10, UIConstants.COLOR_TEXT_MUTED)
	_add_card_spacer(actions_body)
	var replay_btn := _add_card_button(actions_body, "Play Again",
			TerrainToolbar.SECTION_COLORS[TerrainToolbar.Section.GOLFERS])
	replay_btn.name = "TournamentPlayAgainButton"
	replay_btn.pressed.connect(func() -> void: play_again_requested.emit())
	var setup_btn := _add_card_button(actions_body, "Tournament Setup", Color("8fa396"))
	setup_btn.name = "TournamentSetupButton"
	setup_btn.pressed.connect(func() -> void: tournament_setup_requested.emit())
	var menu_btn := _add_card_button(actions_body, "Main Menu", Color("8fa396"))
	menu_btn.name = "TournamentMainMenuButton"
	menu_btn.pressed.connect(func() -> void: main_menu_requested.emit())

## Jump to the results: whoever is still on the course has their card completed and
## the remaining rounds are scored off the field's skill levels.
func _on_play_it_out_pressed() -> void:
	if _tournament_manager:
		_tournament_manager.simulate_remaining_and_complete()
		_refresh_display()

func _create_stat_row(label_text: String, value_text: String, value_color: Color) -> HBoxContainer:
	var row = HBoxContainer.new()

	var label = Label.new()
	label.text = label_text
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)

	var value = Label.new()
	value.text = value_text
	value.add_theme_color_override("font_color", value_color)
	value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	row.add_child(value)

	return row

func _on_host_pressed(tier: int) -> void:
	# Hosting starts the event on the spot — no booking, no waiting for a date.
	if _tournament_manager.host_tournament(tier):
		_refresh_display()

func _on_close_pressed() -> void:
	close_requested.emit()
	hide()

func _on_tournament_scheduled(tier: int, start_day: int) -> void:
	# A tournament hosted from this panel is already playing, so only a booking
	# in someone's diary (e.g. a restored save) is announced as scheduled.
	if start_day > GameManager.current_day:
		EventBus.notify("%s scheduled for Day %d!" % [
			TournamentSystem.get_tier_name(tier), start_day], "success")
	_refresh_display()

func _on_tournament_started(tier: int) -> void:
	var tier_name = TournamentSystem.get_tier_name(tier)
	EventBus.notify("%s has begun — you are in the field!" % tier_name, "success")
	_refresh_pending = true
	_refresh_display()

func _on_tournament_completed(tier: int, results: Dictionary) -> void:
	var tier_name = TournamentSystem.get_tier_name(tier)
	EventBus.notify("%s completed! Winner: %s (%d)" % [tier_name, results.winner_name, results.winning_score], "success")
	_refresh_pending = true
	_refresh_display()
