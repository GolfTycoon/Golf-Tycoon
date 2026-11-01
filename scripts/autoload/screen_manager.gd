extends Node
## Screen - Responsive layout adapter for the whole game (autoload).
##
## The game is designed at a 1600x1000 reference size (see project.godot) and
## renders at the display's native pixel size (stretch mode is "disabled"), so
## one *logical* layout pixel maps to `ui_scale` real display pixels. This
## autoload turns the raw window size into layout decisions:
##
##  * ui_scale - the UI size in real display pixels. At 100% one design pixel
##    is one display pixel. The automatic default follows the device's system
##    display scale (Retina backing scale on macOS, display DPI on Windows,
##    screen density on Android/iOS, devicePixelRatio on the web), so the game
##    is the same comfortable physical size as the rest of the desktop or
##    phone instead of being tiny on a 4K/Retina screen. A player can pin a
##    manual scale instead (Settings -> Display -> UI Scale); it is kept
##    between sessions.
##  * window_size - the logical window: the real window divided by ui_scale.
##    Everything below (compact flags, panels, the world scale) uses this, so
##    a 4K desktop at 200% lays out exactly like a 1920x1080 one.
##  * world_scale - the extra camera zoom applied on top of the player's
##    chosen zoom level. On large logical windows it makes the visible course
##    area track the reference view (a 1920x1080 window sees the same tiles
##    per inch as the 1600x1000 design). On narrow windows (phones, small
##    browser windows) it is floored at 1.0 so tiles never shrink below
##    design size and stay big enough to tap.
##  * compact / portrait flags - narrow or tall windows get a compact HUD
##    (narrower status column, smaller minimap) so everything fits.
##  * touch layout - compact windows and touch-enabled displays get larger
##    controls and a taller bottom dock for comfortable thumb targets.
##  * available_panel_size() - the rect popup panels may occupy, keeping
##    clear of the bottom control bar.
##  * modal_panel_rect() - the rect a modal overlay (the pause menu, a
##    confirmation dialogue) may occupy: the whole window, since a modal
##    covers the HUD and its bottom bar.
##
## The `changed` signal fires whenever the window size (or its derived
## values) change - on live desktop resizes and on mobile rotation.
## `ui_scale_changed` fires when the effective UI scale or the automatic /
## manual choice moves, so the Settings control can follow it.

signal changed(window_size: Vector2, world_scale: float)
signal ui_scale_changed(scale: float, mode: int)

## Reference design resolution.
const BASE_SIZE := Vector2(1600.0, 1000.0)

## Windows narrower than this (or shorter than COMPACT_HEIGHT) use the
## compact HUD: narrower status column, smaller minimap.
const COMPACT_WIDTH := 900.0
const COMPACT_HEIGHT := 640.0

## Physical window widths at or above this scale the world with the window;
## below it the world stays at 1:1 pixel scale so tiles remain tappable.
const WORLD_SCALE_FLOOR_WIDTH := 900.0

## Breathing room a modal overlay keeps from the window edge.
const MODAL_MARGIN := 12.0

## Where the automatic scale and the player's manual choice are kept. Kept in
## step with SaveManager.SETTINGS_PATH; Screen loads it itself because it is
## the first autoload and must size the UI before any screen is built.
const SETTINGS_PATH := "user://settings.cfg"

## UI scale bounds. 100% is the 1600x1000 design at one display pixel per
## design pixel; the top end covers phones and 4K/Retina desktops.
const MIN_UI_SCALE := 0.8
const MAX_UI_SCALE := 4.0
## The Settings slider and the automatic detection share these 5% steps.
const UI_SCALE_STEP := 0.05

## A desktop window never ends up with less logical room than this when the
## automatic scale is chosen, so a small window on a high-DPI display does not
## turn into a giant, cramped UI. Mobile screens are exempt: 360 logical
## pixels wide is a normal phone, not a squeezed desktop.
const MIN_LOGICAL_WIDTH := 1180.0
const MIN_LOGICAL_HEIGHT := 680.0

## How often (seconds) the display scale is re-read, so moving the window
## between monitors with different scaling is followed even when the window
## keeps its size.
const DISPLAY_POLL_INTERVAL := 0.5

## Automatic (follow the device) or a scale the player pinned.
enum UIScaleMode { AUTO, MANUAL }

var window_size: Vector2 = BASE_SIZE
var world_scale: float = 1.0

## Effective UI scale, applied to the root window's content scale.
var ui_scale: float = 1.0
## What the current display and window ask for, whatever the mode.
var detected_ui_scale: float = 1.0
## Short phrase naming the signal the automatic scale came from, ready for
## "detected from %s" in the Settings copy.
var ui_scale_source: String = "the 1600 × 1000 design"
## True when the window itself, rather than the display, decided the scale
## (see MIN_LOGICAL_WIDTH). `display_ui_scale` is what it would otherwise be.
var ui_scale_capped: bool = false
var display_ui_scale: float = 1.0
var ui_scale_mode: int = UIScaleMode.AUTO

## The player's own scale, restored when they turn automatic sizing off.
var _manual_ui_scale: float = 1.0
var _display_poll_elapsed: float = 0.0
var _display_signature: String = ""

func _ready() -> void:
	# Size the UI before any screen is built: autoloads are added in project
	# order, and Screen is first, so the main scene has not run yet.
	_load_ui_scale_preference()
	window_size = _read_window_size()
	world_scale = compute_world_scale(window_size)
	_display_signature = _read_display_signature()
	# React to window resizes/rotation. Polling every frame is cheap enough
	# and also catches web canvas resizes that skip the root signal.
	get_tree().root.size_changed.connect(_on_root_size_changed)

func _process(delta: float) -> void:
	var new_size := _read_window_size()
	if new_size != window_size:
		apply_size(new_size)
	# Native display scaling can change without the window resizing - dragged
	# to another monitor, a tablet rotated, a system scaling change. Re-read
	# it now and then instead of every frame (screen_get_dpi enumerates
	# monitors on Windows).
	_display_poll_elapsed += delta
	if _display_poll_elapsed >= DISPLAY_POLL_INTERVAL:
		_display_poll_elapsed = 0.0
		_poll_display_scale()

func _read_window_size() -> Vector2:
	return get_viewport().get_visible_rect().size

func _on_root_size_changed() -> void:
	_process(0.0)

## Recompute all derived values for a window size and emit `changed` when
## something moved. Safe to call with the current size (no-op).
func apply_size(new_size: Vector2) -> void:
	# A resize or rotation can change the automatic scale too (a windowed
	# window is capped so it keeps room for the layout). Re-detect first, then
	# read the size again: applying a scale changes the logical window.
	if ui_scale_mode == UIScaleMode.AUTO and is_inside_tree() and _display_signature_changed():
		# Only a window/display change can move the automatic scale. A logical
		# size change that came from somewhere else (a scale applied by hand,
		# a test) is left alone instead of being snapped back.
		if _refresh_auto_scale():
			ui_scale_changed.emit(ui_scale, ui_scale_mode)
		new_size = _read_window_size()
	var new_world_scale := compute_world_scale(new_size)
	if new_size == window_size and new_world_scale == world_scale:
		return
	window_size = new_size
	world_scale = new_world_scale
	changed.emit(window_size, world_scale)

## Reference view scale: how big the window is relative to the 1600x1000
## design, limited by the smaller dimension.
static func compute_scale(window: Vector2) -> float:
	return minf(window.x / BASE_SIZE.x, window.y / BASE_SIZE.y)

## Camera scale for a window size (see header). Pure and unit-testable.
static func compute_world_scale(window: Vector2) -> float:
	var s := compute_scale(window)
	var floor_ := minf(1.0, WORLD_SCALE_FLOOR_WIDTH / maxf(window.x, 1.0))
	return maxf(s, floor_)

# =============================================================================
# UI SCALE
# =============================================================================

## Whether the automatic scale should be used (see UIScaleMode).
func uses_automatic_ui_scale() -> bool:
	return ui_scale_mode == UIScaleMode.AUTO

## The percentage shown by the Settings control ("150%").
static func format_ui_scale(scale: float) -> String:
	return "%d%%" % int(roundf(scale * 100.0))

## Snap a scale to the same 5% steps the Settings slider offers and keep it
## inside the supported range. Pure and unit-testable.
static func snap_ui_scale(value: float) -> float:
	return clampf(snappedf(value, 0.05), MIN_UI_SCALE, MAX_UI_SCALE)

## The device's own display scale, as a UI multiplier. Pure and unit-testable.
##
## Godot exposes it differently per platform:
##  * macOS, iOS, the web and Wayland report the backing scale or
##    devicePixelRatio through screen_get_scale().
##  * Windows reports a monitor's effective DPI (96 at 100%, 120 at 125%,
##    144 at 150%, 192 at 200%) and a flat 1.0 from screen_get_scale().
##  * Android's screen_get_scale() is cropped to keep an 800x600 canvas on
##    screen, so its densityDpi (160 = 100%, 480 = 300%) is the real dp
##    scale the phone lays its UI out in.
##  * X11 has no desktop-scale API at all - its DPI is the panel's physical
##    resolution - so the toolkit's GDK_SCALE / QT_SCALE_FACTOR is used when
##    a Linux desktop sets one.
## A scale below 100% is ignored: the game's compact layouts already handle
## small windows, and shrinking text further would make them harder to read.
static func detect_system_ui_scale(system_scale: float, screen_dpi: int,
		platform: String, environment_scale: float = 1.0) -> float:
	var reported := system_scale
	if not is_finite(reported) or reported <= 0.0:
		reported = 1.0
	reported = clampf(reported, 1.0, MAX_UI_SCALE)
	var dpi_scale := 1.0
	if screen_dpi > 0:
		dpi_scale = clampf(float(screen_dpi) / 96.0, 1.0, MAX_UI_SCALE)
	var detected := reported
	match platform:
		"Windows":
			# screen_get_scale() is the display server's default 1.0 here.
			detected = maxf(reported, dpi_scale)
		"Android":
			# densityDpi is the phone's dp scale (160 = 100%, 480 = 300%).
			# screen_get_scale() is capped to avoid cropping an 800x600
			# canvas, which would leave the UI far too small.
			if screen_dpi > 0:
				detected = clampf(float(screen_dpi) / 160.0, 1.0, MAX_UI_SCALE)
			else:
				detected = maxf(1.0, reported)
		"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
			var environment := environment_scale
			if not is_finite(environment) or environment <= 0.0:
				environment = 1.0
			# Wayland's screen scale already carries the compositor choice;
			# X11 only has the toolkit variables.
			detected = maxf(reported, clampf(environment, 1.0, MAX_UI_SCALE))
	return clampf(detected, 1.0, MAX_UI_SCALE)

## The automatic UI scale for a device and window. Pure and unit-testable.
##
## `physical_window` is the real window size in display pixels (not the
## logical one), `mobile` marks phone/tablet platforms that layout in
## density-independent pixels, and `windowed` enables the room cap that keeps
## a small desktop window usable. A maximised/fullscreen window is never
## capped: the player asked for as much room as the display has.
static func compute_auto_ui_scale(physical_window: Vector2, system_scale: float,
		screen_dpi: int, platform: String, mobile: bool = false,
		environment_scale: float = 1.0, windowed: bool = true) -> float:
	var detected := detect_system_ui_scale(
		system_scale, screen_dpi, platform, environment_scale)
	if detected > 1.0 and not mobile and windowed:
		var window := physical_window.max(Vector2.ONE)
		var room := minf(window.x / MIN_LOGICAL_WIDTH, window.y / MIN_LOGICAL_HEIGHT)
		detected = minf(detected, maxf(room, 1.0))
	return snap_ui_scale(detected)

## The desktop toolkit's scale variables, for X11 desktops with no display
## scale of their own. Pure enough to unit-test through the environment.
static func read_environment_display_scale() -> float:
	var scale := 1.0
	for variable in ["GDK_SCALE", "QT_SCALE_FACTOR"]:
		var value := OS.get_environment(variable).strip_edges()
		if value.is_empty():
			continue
		var parsed := value.to_float()
		if is_finite(parsed) and parsed > 0.0:
			scale = maxf(scale, parsed)
	return clampf(scale, 1.0, MAX_UI_SCALE)

## Phone and tablet platforms lay their UI out in density-independent pixels,
## so the automatic scale follows the screen density without the desktop room
## cap. A touch-first web build (a browser on a phone or tablet) counts too.
static func is_mobile_platform(platform: String, touchscreen: bool) -> bool:
	if platform == "Android" or platform == "iOS":
		return true
	return platform == "Web" and touchscreen

## The live automatic scale and where it came from, for Settings. Returns
## {scale, source, system_scale, screen_dpi, platform, capped}.
func detect_ui_scale_info() -> Dictionary:
	var platform := OS.get_name()
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var system_scale := DisplayServer.screen_get_scale(screen)
	var screen_dpi := DisplayServer.screen_get_dpi(screen)
	var environment := read_environment_display_scale()
	var mobile := is_mobile_platform(platform, DisplayServer.is_touchscreen_available())
	var windowed := DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_WINDOWED
	var physical := _read_physical_window_size()
	var scale := compute_auto_ui_scale(physical, system_scale, screen_dpi,
		platform, mobile, environment, windowed)
	var uncapped := detect_system_ui_scale(
		system_scale, screen_dpi, platform, environment)
	var source := "the 1600 × 1000 design"
	if uncapped > 1.0:
		match platform:
			"Windows":
				source = "Windows display scaling"
			"Linux", "FreeBSD", "NetBSD", "OpenBSD", "BSD":
				source = "your desktop's display scale"
			_:
				source = "the system display scale"
	return {
		"scale": scale,
		"display_scale": uncapped,
		"source": source,
		"system_scale": system_scale,
		"screen_dpi": screen_dpi,
		"platform": platform,
		"capped": scale < uncapped,
	}

## Read the preference file. A settings file from before automatic scaling
## stored the effective scale after every display change, so 100% there is the
## old fixed default, not a choice; anything else was a deliberate manual
## scale and is honoured.
func load_ui_scale_from_config(config: ConfigFile) -> void:
	var stored := snap_ui_scale(float(config.get_value("display", "ui_scale", 1.0)))
	var has_mode := config.has_section_key("display", "ui_scale_mode")
	var mode: int = UIScaleMode.AUTO
	if has_mode:
		mode = clampi(int(config.get_value("display", "ui_scale_mode", UIScaleMode.AUTO)),
			UIScaleMode.AUTO, UIScaleMode.MANUAL)
	elif not is_equal_approx(stored, 1.0):
		mode = UIScaleMode.MANUAL
	_manual_ui_scale = stored
	ui_scale_mode = mode
	_apply_loaded_scale()

## Write this preference into an open ConfigFile. `ui_scale` stays the
## effective scale so an older build reading the file still renders at a
## sensible size; `ui_scale_mode` marks whether the player chose it.
func save_ui_scale_to_config(config: ConfigFile) -> void:
	config.set_value("display", "ui_scale_mode", ui_scale_mode)
	config.set_value("display", "ui_scale", ui_scale)

## Choose automatic sizing, or pin the scale the player is looking at.
func set_ui_scale_mode(mode: int, save: bool = true) -> void:
	mode = clampi(mode, UIScaleMode.AUTO, UIScaleMode.MANUAL)
	var mode_changed := mode != ui_scale_mode
	if mode == UIScaleMode.MANUAL and ui_scale_mode == UIScaleMode.AUTO:
		# Turning automatic off starts from what the player can see; the
		# slider then moves them away from it.
		_manual_ui_scale = ui_scale
	ui_scale_mode = mode
	var moved := false
	if mode == UIScaleMode.AUTO:
		moved = _refresh_auto_scale()
	else:
		moved = _apply_effective_scale(_manual_ui_scale)
	if moved or mode_changed:
		ui_scale_changed.emit(ui_scale, ui_scale_mode)
	if save:
		_save_ui_scale_preference()

## Pin a manual scale. Dragging the Settings slider lands here, which is also
## how the automatic mode is left.
func set_ui_scale(value: float, save: bool = true) -> void:
	_manual_ui_scale = snap_ui_scale(value)
	var was_automatic := ui_scale_mode == UIScaleMode.AUTO
	ui_scale_mode = UIScaleMode.MANUAL
	_apply_effective_scale(_manual_ui_scale)
	if was_automatic or not is_equal_approx(_manual_ui_scale, value):
		ui_scale_changed.emit(ui_scale, ui_scale_mode)
	if save:
		_save_ui_scale_preference()

## Back to the shipped default: automatic sizing from this device.
func reset_ui_scale(save: bool = true) -> void:
	_manual_ui_scale = 1.0
	ui_scale_mode = UIScaleMode.AUTO
	_refresh_auto_scale()
	ui_scale_changed.emit(ui_scale, ui_scale_mode)
	if save:
		_save_ui_scale_preference()

## Where "Match this display" points the UI (Settings shows this).
func auto_ui_scale_hint() -> String:
	if ui_scale_capped:
		return "Automatic — %s here so this window keeps room for the layout; this display would use %s." % [
			format_ui_scale(detected_ui_scale), format_ui_scale(display_ui_scale)]
	if detected_ui_scale > 1.0:
		return "Automatic — %s detected from %s. Resize or move the window to check again." % [
			format_ui_scale(detected_ui_scale), ui_scale_source]
	return "Automatic — %s, the size the 1600 × 1000 layout is designed at." % [
		format_ui_scale(detected_ui_scale)]

func _load_ui_scale_preference() -> void:
	var config := ConfigFile.new()
	if config.load(SETTINGS_PATH) == OK:
		load_ui_scale_from_config(config)
	else:
		_manual_ui_scale = 1.0
		ui_scale_mode = UIScaleMode.AUTO
		_apply_loaded_scale()

func _apply_loaded_scale() -> void:
	if ui_scale_mode == UIScaleMode.AUTO:
		_refresh_auto_scale()
	else:
		_apply_effective_scale(_manual_ui_scale)

func _save_ui_scale_preference() -> void:
	var config := ConfigFile.new()
	config.load(SETTINGS_PATH)
	save_ui_scale_to_config(config)
	config.save(SETTINGS_PATH)

## Re-read the display and apply the automatic scale if it is in charge.
## Returns true when the effective scale moved. Callers decide whether to
## announce it, so a listener is never woken by an unchanged poll.
func _refresh_auto_scale() -> bool:
	if not is_inside_tree():
		return false
	var info := detect_ui_scale_info()
	detected_ui_scale = float(info["scale"])
	display_ui_scale = float(info["display_scale"])
	ui_scale_capped = bool(info["capped"])
	ui_scale_source = String(info["source"])
	_display_signature = _read_display_signature()
	if ui_scale_mode != UIScaleMode.AUTO:
		return false
	return _apply_effective_scale(detected_ui_scale)

func _apply_effective_scale(value: float) -> bool:
	if not is_inside_tree():
		return false
	var next := snap_ui_scale(value)
	var root := get_tree().root
	if is_equal_approx(ui_scale, next) and is_equal_approx(root.content_scale_factor, next):
		return false
	ui_scale = next
	root.content_scale_factor = next
	return true

func _poll_display_scale() -> void:
	# A minimised window reports a zero size; leave the scale alone until it
	# comes back.
	if DisplayServer.window_get_mode() == DisplayServer.WINDOW_MODE_MINIMIZED:
		return
	if not _display_signature_changed():
		return
	if _refresh_auto_scale() and ui_scale_mode == UIScaleMode.AUTO:
		ui_scale_changed.emit(ui_scale, ui_scale_mode)
	# In manual mode _refresh_auto_scale only updates the detected size the
	# Settings copy quotes; the player's pinned scale is left alone.

func _display_signature_changed() -> bool:
	return _read_display_signature() != _display_signature

## Everything a scale change depends on, cheap to compare once in a while.
func _read_display_signature() -> String:
	var screen := DisplayServer.window_get_current_screen()
	if screen < 0:
		screen = DisplayServer.get_primary_screen()
	var physical := _read_physical_window_size()
	return "%d:%d:%d:%d:%d:%d" % [
		DisplayServer.window_get_mode(), screen, int(physical.x), int(physical.y),
		roundi(DisplayServer.screen_get_scale(screen) * 100.0),
		DisplayServer.screen_get_dpi(screen),
	]

func _read_physical_window_size() -> Vector2:
	var size := Vector2(DisplayServer.window_get_size())
	if size.x <= 0.0 or size.y <= 0.0:
		size = Vector2(get_tree().root.size)
	return size

func is_compact() -> bool:
	return window_size.x < COMPACT_WIDTH or window_size.y < COMPACT_HEIGHT

func is_portrait() -> bool:
	return window_size.y > window_size.x

func is_landscape() -> bool:
	return window_size.x >= window_size.y

## Whether this window should use thumb-friendly control sizing. Compact
## layouts are treated as touch surfaces even on a desktop so narrow windows
## remain usable; native touch displays get the same layout at larger sizes.
func uses_touch_layout() -> bool:
	return is_compact() or DisplayServer.is_touchscreen_available()

## Bottom control bar height (view/speed controls + tabbed toolbar).
func bottom_bar_height() -> float:
	return float(UIConstants.TOUCH_BOTTOM_BAR_HEIGHT if uses_touch_layout() else UIConstants.BOTTOM_BAR_HEIGHT)

## Vertical space below which popup panels must not sit (the bottom bar
## plus a little breathing room).
func hud_bottom_clearance() -> float:
	return bottom_bar_height() + 8.0

## The largest size a centered popup panel may take while staying fully on
## screen and clear of the bottom bar.
func available_panel_size() -> Vector2:
	var margin := Vector2(16.0, 12.0)
	var size := window_size - Vector2(margin.x * 2.0, margin.y * 2.0 + hud_bottom_clearance())
	return size.max(Vector2(120.0, 120.0))

## Full rect available to popup panels (margins + bottom-bar clearance).
func available_panel_rect() -> Rect2:
	var margin := Vector2(16.0, 12.0)
	return Rect2(
		margin.x, margin.y,
		window_size.x - margin.x * 2.0,
		window_size.y - margin.y * 2.0 - hud_bottom_clearance()
	)

## Full rect available to a modal overlay (the pause menu, a confirmation
## dialogue). A modal dims the whole game and covers the HUD, bottom bar
## included, so unlike a HUD popup it may use the entire window — only a small
## margin is kept as breathing room. On a phone held sideways this is the
## difference between a menu that fits and one squeezed into a narrow strip.
func modal_panel_rect() -> Rect2:
	return Rect2(
		MODAL_MARGIN, MODAL_MARGIN,
		maxf(window_size.x - MODAL_MARGIN * 2.0, 120.0),
		maxf(window_size.y - MODAL_MARGIN * 2.0, 120.0)
	)
