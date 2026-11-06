extends Node
## Backdrops - the background picture and overlay the menus wear (autoload).
##
## Two independent preferences, both chosen in Settings > Display > Background
## and both saved to user://settings.cfg:
##
##   display/menu_background         a catalogue id, or "auto"
##   display/menu_overlay            a catalogue id, or "auto"
##   display/menu_overlay_settings   per-overlay values, e.g. {"lattice": {"angle": 45}}
##
## Auto is the default and is special: instead of one fixed style it resolves
## at each opening from the game's own state. A picture tagged with the current
## course theme wins, then one tagged with the current season, then the shipped
## clubhouse; the overlay follows the same rule. On the title screen there is no
## course yet, so the season alone decides. The shipped catalogue tags Winter
## with the winter season, so Auto quietly changes the title screen's picture
## when the calendar turns - which is the point of the option.
##
## What is on offer - the shipped styles plus every enabled mod's - lives in
## MenuBackdropCatalog. This autoload is the player's side of it: the saved
## choice, the decoded pictures and the resolution a backdrop asks for.
##
## Choices are stored by id, never by index, so installing or reordering mods
## cannot silently move the player's pick to a different picture; and a choice
## whose mod is gone falls back to Auto rather than failing.

signal backdrop_changed

## The stored id that means "decide for me".
const AUTO: String = "auto"
const SETTINGS_SECTION: String = "display"
const BACKGROUND_KEY: String = "menu_background"
const OVERLAY_KEY: String = "menu_overlay"
const OVERLAY_SETTINGS_KEY: String = "menu_overlay_settings"

## The saved background id, or AUTO.
var background_choice: String = AUTO
## The saved overlay id, or AUTO.
var overlay_choice: String = AUTO
## Per-overlay setting values: overlay id -> {setting key: value}.
var overlay_settings: Dictionary = {}

## Decoded pictures, by path, so a screen rebuilt on every resize does not
## decode its file again. Paths that failed are remembered too, so a missing
## file costs one attempt rather than one per rebuild.
var _textures: Dictionary = {}
var _texture_failures: Dictionary = {}


func _ready() -> void:
	# Mods may load after this autoload; the registry's signal is how the
	# catalogue and every open menu learn that new styles are on offer.
	if not ContentRegistry.content_changed.is_connected(_on_content_changed):
		ContentRegistry.content_changed.connect(_on_content_changed)


func _on_content_changed() -> void:
	# A picture can change under the same path (a mod updated in place), so the
	# decoded copies are dropped with the catalogue.
	_textures.clear()
	_texture_failures.clear()
	backdrop_changed.emit()


# ---------------------------------------------------------------------------
# THE PLAYER'S CHOICE
# ---------------------------------------------------------------------------

## Read the saved choice from a settings file. SaveManager calls this once at
## boot, before any menu is built.
func load_from_config(config: ConfigFile) -> void:
	background_choice = _read_choice(config, BACKGROUND_KEY)
	overlay_choice = _read_choice(config, OVERLAY_KEY)
	overlay_settings.clear()
	var raw: Variant = config.get_value(SETTINGS_SECTION, OVERLAY_SETTINGS_KEY, {})
	if raw is Dictionary:
		for overlay_id in raw:
			var values: Variant = raw[overlay_id]
			if values is Dictionary:
				overlay_settings[str(overlay_id)] = (values as Dictionary).duplicate(true)
	backdrop_changed.emit()


## Write the choice into a settings file the caller then saves (the Settings
## page does, so the whole Display section lands in one write).
func save_to_config(config: ConfigFile) -> void:
	config.set_value(SETTINGS_SECTION, BACKGROUND_KEY, background_choice)
	config.set_value(SETTINGS_SECTION, OVERLAY_KEY, overlay_choice)
	config.set_value(SETTINGS_SECTION, OVERLAY_SETTINGS_KEY, overlay_settings.duplicate(true))


## Pick a background style, writing it straight to the player's settings.
func set_background_choice(id: String) -> void:
	set_background_choice_quietly(id)
	_write_to_settings()


## Same, without touching the disk - for the Settings page, which saves the
## whole Display section once the interaction is done.
func set_background_choice_quietly(id: String) -> void:
	var wanted: String = id if id == AUTO or MenuBackdropCatalog.has_backdrop(id) else AUTO
	if background_choice == wanted:
		return
	background_choice = wanted
	backdrop_changed.emit()


func set_overlay_choice(id: String) -> void:
	set_overlay_choice_quietly(id)
	_write_to_settings()


func set_overlay_choice_quietly(id: String) -> void:
	var wanted: String = id if id == AUTO or MenuBackdropCatalog.has_overlay(id) else AUTO
	if overlay_choice == wanted:
		return
	overlay_choice = wanted
	backdrop_changed.emit()


## One of an overlay's own settings (see MenuBackdropCatalog.settings_for),
## clamped to the values the catalogue declares. Returns the value in force.
func set_overlay_setting(overlay_id: String, key: String, value: Variant) -> Variant:
	var resolved: Variant = MenuBackdropCatalog.setting_value(overlay_id, key, value)
	var values: Dictionary = overlay_settings.get(overlay_id, {})
	if values.get(key) == resolved:
		return resolved
	values[key] = resolved
	overlay_settings[overlay_id] = values
	backdrop_changed.emit()
	return resolved


## Back to Auto for both choices, dropping every overlay setting.
func reset_choices() -> void:
	var changed := background_choice != AUTO or overlay_choice != AUTO or not overlay_settings.is_empty()
	background_choice = AUTO
	overlay_choice = AUTO
	overlay_settings.clear()
	if changed:
		backdrop_changed.emit()


# ---------------------------------------------------------------------------
# WHAT TO SHOW RIGHT NOW
# ---------------------------------------------------------------------------

## The background this opening should wear:
##   {id, name, description, image, tint, scrim, texture, texture_missing, automatic}
## `id` is always a real catalogue id (Auto resolves to one), so the Settings
## page can say which picture Auto picked. `texture` is null only when the
## picture cannot be read.
func resolve_background() -> Dictionary:
	var season: String = season_tag()
	var theme: String = theme_tag()
	var chosen: Dictionary
	var automatic := true
	if background_choice != AUTO and MenuBackdropCatalog.has_backdrop(background_choice):
		chosen = MenuBackdropCatalog.backdrop(background_choice)
		automatic = false
	else:
		chosen = _automatic_backdrop(season, theme)
	chosen["automatic"] = automatic
	var image_path: String = str(chosen.get("image", ""))
	chosen["image"] = image_path
	chosen["texture"] = texture_for(image_path)
	chosen["texture_missing"] = not image_path.is_empty() and chosen["texture"] == null
	return chosen


## The overlay this opening should wear:
##   {id, name, description, pattern, color, strength, scale, settings, automatic}
func resolve_overlay() -> Dictionary:
	var season: String = season_tag()
	var theme: String = theme_tag()
	var chosen: Dictionary
	var automatic := true
	if overlay_choice != AUTO and MenuBackdropCatalog.has_overlay(overlay_choice):
		chosen = MenuBackdropCatalog.overlay(overlay_choice)
		automatic = false
	else:
		chosen = _automatic_overlay(season, theme)
	chosen["automatic"] = automatic
	var overlay_id: String = str(chosen.get("id", ""))
	chosen["settings"] = MenuBackdropCatalog.resolved_settings(
		overlay_id, overlay_settings.get(overlay_id, {}))
	return chosen


## The style Auto would pick for the game's current state, without decoding a
## picture - what the Settings page shows beside the Auto option.
func auto_background_id() -> String:
	return str(_automatic_backdrop(season_tag(), theme_tag()).get("id", MenuBackdropCatalog.DEFAULT_BACKDROP_ID))


func auto_overlay_id() -> String:
	return str(_automatic_overlay(season_tag(), theme_tag()).get("id", MenuBackdropCatalog.DEFAULT_OVERLAY_ID))


## Why Auto chose what it chose, in one line for the Settings card.
func auto_explanation() -> String:
	var season: String = season_tag()
	var theme: String = theme_tag()
	var backdrop := _automatic_backdrop(season, theme)
	var overlay := _automatic_overlay(season, theme)
	var backdrop_name: String = str(backdrop.get("name", MenuBackdropCatalog.DEFAULT_BACKDROP_ID.capitalize()))
	var overlay_name: String = str(overlay.get("name", "None"))
	if not theme.is_empty() and _has_tag(backdrop, "themes", theme):
		return "Auto: a %s course picks %s, with the %s overlay." % [
			theme.capitalize(), backdrop_name, overlay_name]
	if not season.is_empty() and _has_tag(backdrop, "seasons", season):
		return "Auto: the %s season picks %s, with the %s overlay." % [
			season.capitalize(), backdrop_name, overlay_name]
	# Neither tag matched: say which picture is showing and what would change it,
	# so the card teaches the season/theme idea instead of just naming a file.
	if overlay_name == "None":
		return "Auto: %s. A season or a course theme can pick a different one." % backdrop_name
	return "Auto: %s, with the %s overlay. A season or a course theme can pick different ones." % [
		backdrop_name, overlay_name]


# ---------------------------------------------------------------------------
# AUTO'S CHOICE
# ---------------------------------------------------------------------------

## Auto prefers, in order: a picture tagged with the current course theme
## (career play only - there is no course on the title screen), then one
## tagged with the current season, then the shipped clubhouse.
func _automatic_backdrop(season: String, theme: String) -> Dictionary:
	var by_theme := _first_tagged(MenuBackdropCatalog.backdrops(), "themes", theme)
	if not by_theme.is_empty():
		return by_theme
	var by_season := _first_tagged(MenuBackdropCatalog.backdrops(), "seasons", season)
	if not by_season.is_empty():
		return by_season
	var fallback := MenuBackdropCatalog.backdrop(MenuBackdropCatalog.DEFAULT_BACKDROP_ID)
	if fallback.is_empty():
		var all := MenuBackdropCatalog.backdrops()
		fallback = all[0] if not all.is_empty() else {"id": "", "name": "None"}
	fallback["id"] = str(fallback.get("id", ""))
	return fallback


## Auto's overlay follows the same rule: a pattern tagged for the season, else
## none, so a picture keeps its own light.
func _automatic_overlay(season: String, theme: String) -> Dictionary:
	var by_theme := _first_tagged(MenuBackdropCatalog.overlays(), "themes", theme)
	if not by_theme.is_empty():
		return by_theme
	var by_season := _first_tagged(MenuBackdropCatalog.overlays(), "seasons", season)
	if not by_season.is_empty():
		return by_season
	var fallback := MenuBackdropCatalog.overlay(MenuBackdropCatalog.DEFAULT_OVERLAY_ID)
	if fallback.is_empty():
		fallback = {"id": MenuBackdropCatalog.DEFAULT_OVERLAY_ID, "pattern": "none", "name": "None"}
	fallback["id"] = str(fallback.get("id", MenuBackdropCatalog.DEFAULT_OVERLAY_ID))
	return fallback


## The first entry in catalogue order carrying `value` in its `key` tag list.
func _first_tagged(entries: Array[Dictionary], key: String, value: String) -> Dictionary:
	if value.is_empty():
		return {}
	for entry in entries:
		if _has_tag(entry, key, value):
			return entry
	return {}


func _has_tag(entry: Dictionary, key: String, value: String) -> bool:
	if value.is_empty():
		return false
	var tags: Variant = entry.get(key, [])
	if not (tags is Array):
		return false
	for tag in tags:
		if str(tag).to_lower() == value:
			return true
	return false


## The season Auto sees, lower-cased ("winter"), or "" in a game where the
## seasons are switched off - Auto then has no seasonal preference to honour.
func season_tag() -> String:
	if SeasonSystem.disabled:
		return ""
	return SeasonSystem.get_season_name(SeasonSystem.get_season(GameManager.current_day)).to_lower()


## The course theme Auto sees, lower-cased ("desert"), or "" while no course is
## being played. The out-of-game menus must not resolve against whatever course
## was last open, so this follows the game mode, not the leftover course data.
func theme_tag() -> String:
	if GameManager.current_course == null:
		return ""
	if GameManager.current_mode == GameManager.GameMode.MAIN_MENU:
		return ""
	return CourseTheme.to_string_name(GameManager.current_theme)


# ---------------------------------------------------------------------------
# PICTURES
# ---------------------------------------------------------------------------

## The picture at `path`, decoded once and shared. Null when it cannot be read:
## pictures are decoded from the raw file (the way mod art is) so a mod's JPEG
## needs no import step, and a failure is remembered rather than retried on
## every repaint.
func texture_for(path: String) -> Texture2D:
	if path.is_empty():
		return null
	if _textures.has(path):
		return _textures[path]
	if _texture_failures.has(path):
		return null
	var texture: Texture2D = null
	if ResourceLoader.exists(path):
		var loaded: Resource = load(path)
		if loaded is Texture2D:
			texture = loaded
	if texture == null and FileAccess.file_exists(path):
		texture = decode_image(FileAccess.get_file_as_bytes(path), path.get_extension())
	if texture == null:
		_texture_failures[path] = true
		return null
	_textures[path] = texture
	return texture


## Decode PNG/JPG/WEBP/BMP bytes into a texture, or null when the bytes are not
## a readable image. Static, so a test or a tool can decode without the autoload.
static func decode_image(bytes: PackedByteArray, extension: String) -> Texture2D:
	if bytes.is_empty():
		return null
	var image := Image.new()
	var ok := false
	match extension.to_lower():
		"png":
			ok = image.load_png_from_buffer(bytes) == OK
		"jpg", "jpeg":
			ok = image.load_jpg_from_buffer(bytes) == OK
		"webp":
			ok = image.load_webp_from_buffer(bytes) == OK
		"bmp":
			ok = image.load_bmp_from_buffer(bytes) == OK
	if not ok or image.is_empty():
		return null
	return ImageTexture.create_from_image(image)


# ---------------------------------------------------------------------------
# SAVING
# ---------------------------------------------------------------------------

func _read_choice(config: ConfigFile, key: String) -> String:
	var raw: Variant = config.get_value(SETTINGS_SECTION, key, AUTO)
	if not (raw is String):
		return AUTO
	var value: String = str(raw).strip_edges().to_lower()
	return value if not value.is_empty() else AUTO


## Write both choices and the overlay settings, leaving every other section of
## settings.cfg as it was.
func _write_to_settings() -> void:
	var config := ConfigFile.new()
	config.load(SaveManager.SETTINGS_PATH)
	save_to_config(config)
	config.save(SaveManager.SETTINGS_PATH)
