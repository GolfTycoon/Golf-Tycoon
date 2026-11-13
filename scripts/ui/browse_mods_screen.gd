extends Control
class_name BrowseModsScreen
## BrowseModsScreen - the mod catalogue: what the player's Mod Repository
## Feeds offer, and one press to install it.
##
## The Official and Example mods do not ship inside the game package; they
## are offered for download here, from the Official Repository on GitHub
## (added by default - see ModRepositoryStore). The screen is also where
## players point the game at any self-hosted feed: a plain JSON document
## listing mods and their zips, served by any web host (the format is in
## repository/README.md and docs/modding.md).
##
## The screen has two panes:
##
##  * Repositories - the feeds the game will show, newest last. Each card
##    can be refreshed (re-fetch its JSON) or removed, and the Official
##    Repository carries its own mark; removing it is allowed, and a
##    one-press restore puts it back. "Add feed" takes any http(s) URL.
##  * Available mods - every entry of every fetched feed, grouped under the
##    feed that offers it, each with its state: Download, Installed, or
##    Update (the feed's version is newer than the installed one).
##
## A download is the ordinary zip install (ModPackage.install_zip through
## ModRepositoryDownloader): the mod arrives switched OFF in the Mods
## screen's library, exactly like an installed zip - installing is never
## enabling, and the Mods screen's tick and Back still stand between a
## stranger's zip and a running game. Nothing here stages a loadout, so
## Back on this screen is just Back.
##
## The screen sits on the same MenuBackdrop as the Mods screen and composes
## the same way: both panes side by side on desktop and tablet, the same two
## panes behind Repositories / Mods tabs on a phone held upright.

signal back_requested()

const Kit := preload("res://scripts/ui/components/menu_screen_kit.gd")

const COLOR_SURFACE := MenuStyle.SHEET_BG
const COLOR_SURFACE_RAISED := MenuStyle.RAIL_BG
const COLOR_SURFACE_INSET := MenuStyle.INSET_BG
const COLOR_TEXT_BRIGHT := MenuStyle.TITLE_COLOR
const COLOR_TEXT_QUIET := UIConstants.COLOR_TEXT_MUTED
const COLOR_GOLD := MenuStyle.ACCENT_PRIMARY
const COLOR_MINT := MenuStyle.ACCENT_SECONDARY

const ROW_HEIGHT := 64.0
const ROW_GAP := 8
const SECTION_GAP := 14
## The picture inside a list row (the default mark; a downloaded mod's own
## icon shows once the Mods screen lists it).
const ROW_ICON_SIZE := 44.0
const MIN_REPOSITORIES_WIDTH := 340.0
const MIN_AVAILABLE_WIDTH := 420.0

const TITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-Bold.ttf")
const SUBTITLE_FONT: Font = preload("res://assets/fonts/PixelifySans-SemiBold.ttf")
const BODY_FONT: Font = preload("res://assets/fonts/PixelifySans-Regular.ttf")

## Row badge text for each state of a feed entry against the player's
## library. Pure, unit-tested: `installed_version` is what ModManager knows
## ("" when the mod is not installed), `feed_version` what the feed claims
## ("" when it does not say).
enum EntryState { DOWNLOAD, INSTALLED, UPDATE }

## The player's feed list. Created over the real user folder; tests swap in
## a throwaway store before the screen joins the tree.
var store: ModRepositoryStore

## The network layer. Created in _ready unless already set; tests inject a
## stub with a `fetch_override` before adding the screen to the tree.
var downloader: ModRepositoryDownloader

## url -> {status: String, feed: ModRepositoryFeed, errors: Array[String]}.
## Status is "fetching", "ok" or "error".
var _feed_states: Dictionary = {}
## Ids with a download in flight, so their rows show progress instead of a
## button. One download runs at a time: the install it ends with re-scans
## the whole library.
var _downloading_id: String = ""
var _last_message: String = ""

var _repositories_box: VBoxContainer = null
var _available_box: VBoxContainer = null
var _repositories_empty: Label = null
var _available_empty: Label = null
var _status: Label = null
var _restore_button: Button = null
var _add_button: Button = null
var _add_dialog: AddRepositoryDialog = null

var _tabs: HBoxContainer = null
var _repositories_panel: PanelContainer = null
var _available_panel: PanelContainer = null
## Phone portrait flips between the two panes with tabs.
var _repositories_shown := true

var _layout_mode: int = -1
var _built_size := Vector2.ZERO


func _init() -> void:
	store = ModRepositoryStore.new()


func _ready() -> void:
	name = "BrowseModsScreen"
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	if downloader == null:
		downloader = ModRepositoryDownloader.new()
		downloader.name = "Downloader"
		add_child(downloader)
	visibility_changed.connect(_on_visibility_changed)
	if has_node("/root/Screen"):
		Screen.changed.connect(_on_screen_changed)
	_build()
	refresh_all_feeds()


func _exit_tree() -> void:
	if has_node("/root/Screen") and Screen.changed.is_connected(_on_screen_changed):
		Screen.changed.disconnect(_on_screen_changed)


func _window_size() -> Vector2:
	return Kit.window_size_of(self)


func _on_screen_changed(window_size: Vector2, _scale: float) -> void:
	var mode := Kit.layout_mode_for(window_size)
	var width_delta := absf(window_size.x - _built_size.x)
	var height_delta := absf(window_size.y - _built_size.y)
	var needs_remeasure := width_delta > maxf(96.0, _built_size.x * 0.14) \
		or height_delta > maxf(72.0, _built_size.y * 0.14)
	if mode != _layout_mode or needs_remeasure:
		_build()


func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event.is_action_pressed("cancel"):
		leave()
		get_viewport().set_input_as_handled()


func _on_visibility_changed() -> void:
	# Nothing to unwind: no staged state. Kept for symmetry with the other
	# fullscreen screens and so a hidden screen stops mid-flight redraws.
	pass


# =============================================================================
# BUILDING
# =============================================================================

func _build() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for child in get_children():
		# The downloader is the screen's working node, not its chrome: a
		# rebuild for a new window shape must not throw the network layer
		# (or a fetch it is running) away.
		if child == downloader:
			continue
		remove_child(child)
		child.queue_free()

	_repositories_box = null
	_available_box = null
	_repositories_empty = null
	_available_empty = null
	_status = null
	_restore_button = null
	_add_button = null
	_add_dialog = null
	_tabs = null
	_repositories_panel = null
	_available_panel = null

	_layout_mode = Kit.layout_mode_for(_window_size())
	_built_size = _window_size()

	var backdrop := MenuBackdrop.new()
	backdrop.name = "Backdrop"
	backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(backdrop)

	var frame := MarginContainer.new()
	frame.name = "Frame"
	frame.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var pad := Kit.outer_padding(_layout_mode, _built_size)
	for side in ["margin_left", "margin_right", "margin_top", "margin_bottom"]:
		frame.add_theme_constant_override(side, pad)
	add_child(frame)

	var page := VBoxContainer.new()
	page.name = "Page"
	page.add_theme_constant_override("separation", Kit.page_separation(_layout_mode))
	page.size_flags_vertical = Control.SIZE_EXPAND_FILL
	frame.add_child(page)

	page.add_child(_build_header(_layout_mode))

	match _layout_mode:
		Kit.LayoutMode.PHONE_PORTRAIT:
			page.add_child(_build_phone_portrait_body())
			page.add_child(_build_status_strip())
		_:
			page.add_child(_build_desktop_body())
			page.add_child(_build_status_strip())

	_sync_panes()
	refresh()


func _build_header(mode: int) -> Control:
	return Kit.make_screen_header(mode, "Browse Mods", leave, null, PixelIcon.Kind.GLOBE)


func _build_desktop_body() -> Control:
	var body := HBoxContainer.new()
	body.name = "RepositoriesAndCatalogue"
	body.add_theme_constant_override("separation", 16)
	body.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var repositories := _build_repositories_panel()
	repositories.custom_minimum_size.x = clampf(MIN_REPOSITORIES_WIDTH, 100.0,
		_built_size.x - MIN_AVAILABLE_WIDTH - 24.0)
	repositories.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(repositories)

	var available := _build_available_panel()
	available.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	available.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body.add_child(available)
	return body


func _build_phone_portrait_body() -> Control:
	var scroll := ScrollContainer.new()
	scroll.name = "PhoneBrowseScroll"
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO

	var content := VBoxContainer.new()
	content.name = "BrowseJournal"
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 8)
	scroll.add_child(content)

	_tabs = HBoxContainer.new()
	_tabs.name = "BrowseTabs"
	_tabs.add_theme_constant_override("separation", 6)
	_tabs.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for tab in ["Repositories", "Mods"]:
		var is_catalogue: bool = tab == "Mods"
		var button := _button(tab, func() -> void:
			_repositories_shown = not is_catalogue
			_sync_panes())
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_tabs.add_child(button)
	content.add_child(_tabs)

	var repositories := _build_repositories_panel(Kit.outer_padding(_layout_mode, _built_size))
	repositories.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(repositories)

	var available := _build_available_panel()
	available.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_child(available)
	return scroll


func _build_repositories_panel(pad: int = 12) -> PanelContainer:
	var panel := Kit.make_panel(COLOR_SURFACE, MenuStyle.with_alpha(UIConstants.COLOR_BORDER, 0.42))
	panel.name = "RepositoriesPanel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", 10)
	margin.add_theme_constant_override("margin_bottom", 10)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.name = "RepositoriesStack"
	stack.add_theme_constant_override("separation", 8)
	margin.add_child(stack)

	var head := _label("MOD REPOSITORY FEEDS", 16, COLOR_GOLD, SUBTITLE_FONT)
	stack.add_child(head)

	var blurb := _label(
		"Feeds list the mods they offer. Add any self-hosted feed by its address.",
		12, COLOR_TEXT_QUIET)
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	stack.add_child(blurb)

	_add_button = _button("+ Add feed", _on_add_feed_pressed)
	_add_button.name = "AddFeedButton"
	_add_button.tooltip_text = "Add a mod repository feed by its http(s) address"
	stack.add_child(_add_button)

	_restore_button = _button("Restore Official Repository", _on_restore_official_pressed)
	_restore_button.name = "RestoreOfficialButton"
	_restore_button.tooltip_text = "Put the game's own repository back on the list"
	_restore_button.visible = not store.official_repository_present()
	stack.add_child(_restore_button)

	var list_scroll := ScrollContainer.new()
	list_scroll.name = "RepositoriesScroll"
	list_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	list_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	list_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	list_scroll.custom_minimum_size.y = ROW_HEIGHT * 2.0 + 10.0
	stack.add_child(list_scroll)

	var list_content := VBoxContainer.new()
	list_content.name = "RepositoriesContent"
	list_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list_content.add_theme_constant_override("separation", 0)
	list_scroll.add_child(list_content)

	_repositories_empty = _label("", 13, COLOR_TEXT_QUIET)
	_repositories_empty.name = "RepositoriesEmptyNote"
	_repositories_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_repositories_empty.visible = false
	list_content.add_child(_repositories_empty)

	_repositories_box = VBoxContainer.new()
	_repositories_box.name = "RepositoryRows"
	_repositories_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_repositories_box.add_theme_constant_override("separation", ROW_GAP)
	list_content.add_child(_repositories_box)

	_repositories_panel = panel
	return panel


func _build_available_panel(pad: int = 14) -> PanelContainer:
	var panel := Kit.make_panel(COLOR_SURFACE_RAISED,
		MenuStyle.with_alpha(MenuStyle.ACCENT_SECONDARY, 0.42))
	panel.name = "AvailablePanel"
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", pad)
	margin.add_theme_constant_override("margin_right", pad)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	panel.add_child(margin)

	var stack := VBoxContainer.new()
	stack.name = "AvailableStack"
	stack.add_theme_constant_override("separation", 8)
	stack.size_flags_vertical = Control.SIZE_EXPAND_FILL
	margin.add_child(stack)

	var head := _label("AVAILABLE MODS", 16, COLOR_GOLD, SUBTITLE_FONT)
	stack.add_child(head)

	var catalogue_scroll := ScrollContainer.new()
	catalogue_scroll.name = "AvailableScroll"
	catalogue_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	catalogue_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	catalogue_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	catalogue_scroll.custom_minimum_size.y = ROW_HEIGHT * 3.0 + 10.0
	stack.add_child(catalogue_scroll)

	var catalogue_content := VBoxContainer.new()
	catalogue_content.name = "AvailableContent"
	catalogue_content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	catalogue_content.add_theme_constant_override("separation", 0)
	catalogue_scroll.add_child(catalogue_content)

	_available_empty = _label("", 13, COLOR_TEXT_QUIET)
	_available_empty.name = "AvailableEmptyNote"
	_available_empty.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_available_empty.visible = false
	catalogue_content.add_child(_available_empty)

	_available_box = VBoxContainer.new()
	_available_box.name = "FeedSections"
	_available_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_available_box.add_theme_constant_override("separation", SECTION_GAP)
	catalogue_content.add_child(_available_box)

	_available_panel = panel
	return panel


func _build_status_strip() -> Control:
	var strip := PanelContainer.new()
	strip.name = "StatusStrip"
	strip.add_theme_stylebox_override("panel",
		PixelButtonStyle.card_style(COLOR_SURFACE_INSET, PixelButtonStyle.State.NORMAL,
			COLOR_SURFACE_INSET, 8, 4, 4))
	var margin := MarginContainer.new()
	for side in ["margin_left", "margin_right"]:
		margin.add_theme_constant_override(side, 10)
	margin.add_theme_constant_override("margin_top", 6)
	margin.add_theme_constant_override("margin_bottom", 6)
	strip.add_child(margin)
	_status = _label("", 13, COLOR_MINT)
	_status.name = "StatusLabel"
	_status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status.mouse_filter = Control.MOUSE_FILTER_PASS
	margin.add_child(_status)
	return strip


func _sync_panes() -> void:
	if _tabs == null:
		if _repositories_panel != null:
			_repositories_panel.visible = true
		if _available_panel != null:
			_available_panel.visible = true
		return
	_repositories_panel.visible = _repositories_shown
	_available_panel.visible = not _repositories_shown


# =============================================================================
# DATA: THE FEEDS
# =============================================================================

## Fetch every feed on the list. Feeds that are already being fetched are
## left alone, so mashing Refresh cannot pile requests up.
func refresh_all_feeds() -> void:
	for record in store.get_repositories():
		refresh_feed(str(record.get("url", "")))


func refresh_feed(url: String) -> void:
	if url.is_empty() or is_fetching(url):
		return
	_feed_states[url] = {"status": "fetching", "feed": null, "errors": [] as Array[String]}
	refresh()
	downloader.fetch_feed(url, _on_feed_fetched.bind(url))


func is_fetching(url: String) -> bool:
	return downloader != null and downloader.is_fetching(url)


func _on_feed_fetched(result: Dictionary, url: String) -> void:
	var feed: ModRepositoryFeed = result.get("feed", null)
	var errors: Array[String] = []
	for error in result.get("errors", []):
		errors.append(str(error))
	if bool(result.get("ok", false)) and feed != null:
		_feed_states[url] = {"status": "ok", "feed": feed, "errors": errors}
		store.note_feed_name(url, feed.name)
	else:
		_feed_states[url] = {"status": "error", "feed": null, "errors": errors}
	refresh()


## The fetched feed for `url`, or null while it is fetching, unanswerable
## or not on the list.
func feed_for(url: String) -> ModRepositoryFeed:
	var state: Dictionary = _feed_states.get(url, {})
	var feed: Variant = state.get("feed", null)
	return feed if feed is ModRepositoryFeed else null


func feed_state_for(url: String) -> Dictionary:
	return _feed_states.get(url, {})


## Every fetched feed's entries flattened for counting and lookups.
func available_entries() -> Array:
	var entries: Array = []
	for record in store.get_repositories():
		var feed := feed_for(str(record.get("url", "")))
		if feed == null:
			continue
		for entry in feed.entries:
			entries.append(entry)
	return entries


## The feed entry for a mod id, searching the feeds in the order the
## player listed them. (The same id on two feeds resolves to the first
## feed that offers it.)
func entry_for(mod_id: String) -> Dictionary:
	for record in store.get_repositories():
		var feed := feed_for(str(record.get("url", "")))
		if feed == null:
			continue
		var entry := feed.entry_for(mod_id)
		if not entry.is_empty():
			return entry
	return {}


# =============================================================================
# DATA: THE ENTRIES AGAINST THE LIBRARY
# =============================================================================

## What the row for a feed entry says about the player's library: not
## installed (Download), installed at this version (Installed), or
## installed but older than the feed's version (Update). Pure, unit-tested.
static func entry_state(installed_version: String, feed_version: String) -> int:
	if installed_version.is_empty():
		return EntryState.DOWNLOAD
	if feed_version.is_empty():
		return EntryState.INSTALLED
	return EntryState.UPDATE if ModManifest.compare_versions(installed_version, feed_version) < 0 \
		else EntryState.INSTALLED


static func entry_state_label(state: int) -> String:
	match state:
		EntryState.INSTALLED:
			return "Installed"
		EntryState.UPDATE:
			return "Update"
	return "Download"


static func entry_state_detail(installed_version: String, feed_version: String, state: int) -> String:
	match state:
		EntryState.INSTALLED:
			return "installed %s" % installed_version if not installed_version.is_empty() else "installed"
		EntryState.UPDATE:
			return "installed %s  →  %s available" % [installed_version, feed_version]
	return "not installed"


## The version of this mod in the player's library, "" when it is not
## installed (asked of the live ModManager so an install flips its row).
func installed_version_of(mod_id: String) -> String:
	return ModManager.get_mod_version(mod_id)


# =============================================================================
# REFRESH: THE ROWS
# =============================================================================

## Rebuild the panes from the store and the fetched feeds. Rows are rebuilt
## rather than kept: this screen has no in-row editing to protect, and the
## catalogue changes wholesale when a feed lands or a download finishes.
func refresh() -> void:
	_sync_repository_rows()
	_sync_available_rows()
	_update_status()


func _sync_repository_rows() -> void:
	if _repositories_box == null:
		return
	# Out of the tree first, then queued for freeing: a rebuild happens on
	# every fetch, and a node left in the tree until its free would claim
	# the name of the row replacing it.
	for child in _repositories_box.get_children():
		_repositories_box.remove_child(child)
		child.queue_free()
	var records := store.get_repositories()
	for index in records.size():
		_repositories_box.add_child(_make_repository_row(records[index], index))
	if _repositories_empty != null:
		_repositories_empty.text = repository_empty_text(records.size())
		_repositories_empty.visible = records.is_empty()
	if _restore_button != null:
		_restore_button.visible = not store.official_repository_present()


func _make_repository_row(record: Dictionary, index: int) -> Control:
	var url := str(record.get("url", ""))
	var row := PanelContainer.new()
	row.name = "RepositoryRow_%d" % index
	row.set_meta("url", url)
	row.add_theme_stylebox_override("panel",
		PixelButtonStyle.card_style(COLOR_SURFACE_INSET, PixelButtonStyle.State.NORMAL,
			COLOR_SURFACE_INSET, 8, 6, 6))
	row.custom_minimum_size.y = 84.0

	var line := HBoxContainer.new()
	line.add_theme_constant_override("separation", 8)
	row.add_child(line)

	var text := VBoxContainer.new()
	text.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	text.add_theme_constant_override("separation", 2)
	line.add_child(text)

	var title := HBoxContainer.new()
	title.add_theme_constant_override("separation", 6)
	text.add_child(title)
	var name_label := _label(_repository_title(record), 14, COLOR_TEXT_BRIGHT, SUBTITLE_FONT)
	name_label.name = "RepoName"
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.clip_text = true
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.add_child(name_label)
	if bool(record.get("official", false)) or store.is_official(url):
		var badge := _label("OFFICIAL", 10, COLOR_GOLD, SUBTITLE_FONT)
		badge.name = "OfficialBadge"
		title.add_child(badge)

	var url_label := _label(url, 11, COLOR_TEXT_QUIET)
	url_label.name = "RepoUrl"
	url_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	url_label.clip_text = true
	text.add_child(url_label)

	var state := feed_state_for(url)
	var status_text := _repository_status_text(url, state)
	var status_label := _label(status_text, 11,
		COLOR_MINT if str(state.get("status", "")) == "ok" else COLOR_TEXT_QUIET)
	status_label.name = "RepoStatus"
	status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_label.clip_text = true
	text.add_child(status_label)

	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", 4)
	line.add_child(buttons)
	var refresh_button := _small_button("Refresh", _on_refresh_feed_pressed.bind(url))
	refresh_button.name = "RefreshButton"
	refresh_button.disabled = str(state.get("status", "")) == "fetching"
	buttons.add_child(refresh_button)
	var remove_button := _small_button("Remove", _on_remove_feed_pressed.bind(url))
	remove_button.name = "RemoveButton"
	buttons.add_child(remove_button)
	return row


## A repository card's first line: the name its feed gave itself, or the
## Official Repository's name, or just its address until it answers.
static func _repository_title(record: Dictionary) -> String:
	var name_value := str(record.get("name", "")).strip_edges()
	if not name_value.is_empty():
		return name_value
	return "Repository"


func _repository_status_text(url: String, state: Dictionary) -> String:
	match str(state.get("status", "")):
		"fetching":
			return "Fetching…"
		"ok":
			var feed := feed_for(url)
			var count := feed.entry_count() if feed != null else 0
			var line := "%d mod%s on offer" % [count, "" if count == 1 else "s"]
			if not state.get("errors", []).is_empty():
				line += "  ·  %s" % "; ".join(state.get("errors", []))
			return line
		"error":
			return "Could not read this feed: %s" % "; ".join(state.get("errors", ["unknown error"]))
	return "Not fetched yet."


func _sync_available_rows() -> void:
	if _available_box == null:
		return
	for child in _available_box.get_children():
		_available_box.remove_child(child)
		child.queue_free()
	var records := store.get_repositories()
	var shown := 0
	for index in records.size():
		var url := str(records[index].get("url", ""))
		var feed := feed_for(url)
		if feed == null:
			continue
		_available_box.add_child(_make_feed_section(records[index], feed, index))
		shown += feed.entries.size()
	if _available_empty != null:
		_available_empty.text = available_empty_text(records.size(), shown)
		_available_empty.visible = shown == 0


func _make_feed_section(record: Dictionary, feed: ModRepositoryFeed, index: int) -> Control:
	var section := VBoxContainer.new()
	section.name = "FeedSection_%d" % index
	section.set_meta("url", str(record.get("url", "")))
	section.add_theme_constant_override("separation", ROW_GAP)

	var head := HBoxContainer.new()
	head.add_theme_constant_override("separation", 8)
	section.add_child(head)
	var title := _label(feed.name, 14, COLOR_TEXT_BRIGHT, SUBTITLE_FONT)
	title.name = "SectionTitle"
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.clip_text = true
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	head.add_child(title)
	var count := _label("%d mod%s" % [feed.entry_count(), "" if feed.entry_count() == 1 else "s"],
		11, COLOR_TEXT_QUIET)
	head.add_child(count)

	var sorted := feed.entries.duplicate()
	sorted.sort_custom(ModRepositoryFeed.entry_before)
	for entry in sorted:
		section.add_child(_make_entry_row(entry))
	return section


func _make_entry_row(entry: Dictionary) -> Control:
	var mod_id := str(entry.get("id", ""))
	var state := entry_state(installed_version_of(mod_id), str(entry.get("version", "")))
	var row := HBoxContainer.new()
	row.name = "ModRow_" + mod_id.replace(".", "_").replace("-", "_")
	row.set_meta("mod_id", mod_id)
	row.custom_minimum_size.y = ROW_HEIGHT
	row.add_theme_constant_override("separation", 6)

	var card := Button.new()
	card.name = "ModCard"
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	card.custom_minimum_size.y = ROW_HEIGHT
	card.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	card.clip_text = false
	card.icon_alignment = HORIZONTAL_ALIGNMENT_LEFT
	card.vertical_icon_alignment = VERTICAL_ALIGNMENT_CENTER
	card.add_theme_constant_override("icon_max_width", int(ROW_ICON_SIZE))
	card.add_theme_constant_override("h_separation", 10)
	card.icon = ModsScreen.fallback_icon_texture()
	card.tooltip_text = _entry_tooltip(entry)
	Kit.paint_utility_button(card, false)
	row.add_child(card)

	var action := Button.new()
	action.name = "DownloadButton"
	action.custom_minimum_size = Vector2(108.0, 44.0)
	Kit.paint_action(action, state != EntryState.INSTALLED)
	_paint_entry_button(action, entry, state)
	action.pressed.connect(_on_download_pressed.bind(mod_id))
	row.add_child(action)
	return row


static func _entry_tooltip(entry: Dictionary) -> String:
	var lines: Array[String] = []
	var description := str(entry.get("description", ""))
	if not description.is_empty():
		lines.append(description)
	var author := str(entry.get("author", ""))
	if not author.is_empty():
		lines.append("by %s" % author)
	var version := str(entry.get("version", ""))
	if not version.is_empty():
		lines.append("version %s" % version)
	return "\n".join(lines)


func _paint_entry_button(button: Button, entry: Dictionary, state: int) -> void:
	var mod_id := str(entry.get("id", ""))
	var downloading := mod_id == _downloading_id
	if downloading:
		var progress := downloader.progress_of(str(entry.get("download_url", ""))) \
			if downloader != null else -1.0
		button.text = "… %d%%" % roundi(progress * 100.0) if progress >= 0.0 else "Downloading…"
		button.disabled = true
		button.tooltip_text = "Downloading - the Mods screen will list it when it lands"
		return
	match state:
		EntryState.INSTALLED:
			button.text = "Installed"
			button.disabled = true
			button.tooltip_text = "Already installed. Uninstall or update it from the Mods screen."
		EntryState.UPDATE:
			button.text = "Update"
			button.disabled = false
			button.tooltip_text = "Download %s and replace the installed copy" % str(entry.get("version", ""))
		_:
			button.text = "Download"
			button.disabled = false
			button.tooltip_text = "Download into your mods library (stays switched off)"


func _update_status() -> void:
	if _status == null:
		return
	if not _last_message.is_empty():
		_status.text = _last_message
	elif not _downloading_id.is_empty():
		_status.text = "Downloading %s - it lands switched off in your Mods screen." % _downloading_id
	else:
		var feeds := store.repository_count()
		var fetched := 0
		var entries := 0
		for record in store.get_repositories():
			var feed := feed_for(str(record.get("url", "")))
			if feed != null:
				fetched += 1
				entries += feed.entry_count()
		_status.text = _summary_text(feeds, fetched, entries,
			store.official_repository_present())
	_status.tooltip_text = _status.text


## The bottom line when nothing more specific happened. Pure, unit-tested.
static func _summary_text(feeds: int, fetched: int, entries: int, official_present: bool) -> String:
	if feeds == 0:
		return "No repository feeds. Add one below, or restore the Official Repository."
	var text := "%d of %d feeds fetched · %d mods on offer" % [fetched, feeds, entries]
	if not official_present:
		text += " · the Official Repository is not on the list"
	return text


static func repository_empty_text(count: int) -> String:
	if count == 0:
		return "No feeds. Add one by its address, or restore the Official Repository."
	return ""


static func available_empty_text(repository_count: int, entry_count: int) -> String:
	if repository_count == 0:
		return "Nothing to browse: add a repository feed first."
	if entry_count == 0:
		return "The feeds on your list have not offered any mods yet. Refresh them, or add another feed."
	return ""


# =============================================================================
# ACTIONS
# =============================================================================

func _on_add_feed_pressed() -> void:
	if is_instance_valid(_add_dialog):
		return
	_add_dialog = AddRepositoryDialog.new(store)
	_add_dialog.added.connect(_on_feed_added)
	_add_dialog.tree_exited.connect(func() -> void: _add_dialog = null)
	add_child(_add_dialog)


func _on_feed_added(url: String) -> void:
	refresh_feed(url)


func _on_restore_official_pressed() -> void:
	if store.restore_official_repository():
		refresh_feed(ModRepositoryStore.OFFICIAL_REPOSITORY_URL)


func _on_refresh_feed_pressed(url: String) -> void:
	refresh_feed(url)


func _on_remove_feed_pressed(url: String) -> void:
	var record := store.repository_for(url)
	var result: Dictionary = store.remove_repository(url)
	if bool(result.get("ok", false)):
		_feed_states.erase(url)
		_last_message = "Removed %s. It can be added again by its address." % _repository_title(record)
		refresh()


func _on_download_pressed(mod_id: String) -> void:
	if _downloading_id == mod_id:
		return
	if not _downloading_id.is_empty():
		_last_message = "One download at a time: %s is still downloading." % _display_name_of(_downloading_id)
		refresh()
		return
	var entry := entry_for(mod_id)
	if entry.is_empty():
		_last_message = "That mod is not on any of your feeds any more; refresh them."
		refresh()
		return
	_downloading_id = mod_id
	_last_message = ""
	refresh()
	downloader.download_and_install(entry, _on_download_finished.bind(mod_id))


func _on_download_finished(result: Dictionary, mod_id: String) -> void:
	_downloading_id = ""
	var errors: Array = result.get("errors", [])
	if bool(result.get("ok", false)):
		# The catalogue is the live library now: the new mod joins the Mods
		# screen's list (at the bottom, switched off) straight away.
		ModManager.discover()
		var entry: Dictionary = result.get("entry", {})
		_last_message = "Installed %s. It is switched off: find it in your Mods screen, tick it, and leave that screen to load it."
		_last_message %= _entry_display_name(entry, mod_id)
	else:
		_last_message = "Could not install %s: %s" % [_display_name_of(mod_id),
			"; ".join(errors) if not errors.is_empty() else "unknown error"]
	refresh()


func _display_name_of(mod_id: String) -> String:
	return _entry_display_name(entry_for(mod_id), mod_id)


static func _entry_display_name(entry: Dictionary, mod_id: String) -> String:
	var name_value := str(entry.get("name", "")).strip_edges()
	return name_value if not name_value.is_empty() else mod_id


## Let the status line settle back to the summary on the next refresh
## (called by the screen's owner when it reopens the screen).
func clear_message() -> void:
	_last_message = ""


func leave() -> void:
	back_requested.emit()


# =============================================================================
# PROGRESS REDRAW
# =============================================================================

func _process(_delta: float) -> void:
	if _downloading_id.is_empty():
		set_process(false)
		return
	var entry := entry_for(_downloading_id)
	if entry.is_empty():
		return
	var url := str(entry.get("download_url", ""))
	if downloader != null and downloader.is_fetching(url):
		var action := _download_button_for(_downloading_id)
		if action != null:
			_paint_entry_button(action, entry,
				entry_state(installed_version_of(_downloading_id), str(entry.get("version", ""))))
		if _status != null and _last_message.is_empty():
			var progress := downloader.progress_of(url)
			_status.text = "Downloading %s%s." % [_display_name_of(_downloading_id),
				" - %d%%" % roundi(progress * 100.0) if progress >= 0.0 else ""]
			_status.tooltip_text = _status.text


func _download_button_for(mod_id: String) -> Button:
	if _available_box == null:
		return null
	for section in _available_box.get_children():
		var row := section.get_node_or_null("ModRow_" + mod_id.replace(".", "_").replace("-", "_"))
		if row != null:
			return row.get_node("DownloadButton") as Button
	return null


# =============================================================================
# LOOK AND FEEL
# =============================================================================

func _label(text: String, font_size: int = 14, color: Color = COLOR_TEXT_BRIGHT,
		font: Font = BODY_FONT) -> Label:
	var label := Label.new()
	label.text = text
	label.add_theme_font_override("font", font)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size.y = 44.0
	Kit.paint_utility_button(button, false)
	button.pressed.connect(action)
	return button


func _small_button(text: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = text
	button.custom_minimum_size = Vector2(88.0, 32.0)
	button.add_theme_font_size_override("font_size", 11)
	Kit.paint_utility_button(button, false)
	button.pressed.connect(action)
	return button
