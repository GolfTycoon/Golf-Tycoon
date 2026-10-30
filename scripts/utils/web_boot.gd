class_name WebBoot
extends RefCounted
## The game's end of the web build's loader handshake.
##
## On the web the game is wrapped in the exported shell's own loading screen
## (web/custom_shell.html): artwork, a progress bar and a stage line over the
## canvas while index.wasm and the .pck download. Draining that bar is only half
## the wait. The engine then boots the main scene, and on a low-end device that
## is many seconds of uninterrupted work during which the browser cannot repaint
## — the loader's animation stops dead and "Starting up 100%" sits on screen
## looking like a crash.
##
## So the main scene builds itself in slices (Main._ready) and reports each step
## here between slices, which gives the browser the frame it needs to paint and
## animate. The title screen is only uncovered when `menu_ready()` says it is
## really up, rather than when the engine's startGame() promise resolves: on the
## web that promise resolves as soon as the engine is up, which the slicing makes
## much earlier than a finished scene.
##
## Away from the web there is no shell to talk to and every call here is a
## no-op: desktop builds keep the engine's own boot splash up until the first
## frame (application/boot_splash in project.godot), so nothing is ever seen
## half-built and nothing needs reporting.

## The object the exported shell puts on `window` for us (see custom_shell.html).
const BRIDGE := "window.GolfTycoonBoot"

## Reported once per process. The shell ignores repeats as well; this just keeps
## the eval off a path that runs every time the player returns to the menu.
static var _menu_reported: bool = false

## The last stage reported, so a test or a bug report can see how far a startup
## got. Kept on every platform, not just the web.
static var last_stage: String = ""

## Force the sliced startup on a platform that would otherwise do it in one go.
## Set by tests, and by the `--split-startup` command-line argument, so the
## browser's path can be exercised (and profiled) without a browser.
static var split_startup_forced: bool = false

## True in the browser build, where the exported shell is the thing waiting.
static func is_web() -> bool:
	return OS.has_feature("web")

## Whether the main scene should build itself in slices (see Main._ready). Every
## web build does; anywhere else it is opt-in, see split_startup_forced.
static func split_startup() -> bool:
	return is_web() or split_startup_forced or OS.get_cmdline_user_args().has("--split-startup")

## Tell the shell's loading screen what the scene is busy with, e.g.
## "Surveying the grounds". No-op away from the web, apart from remembering it.
static func set_stage(stage: String) -> void:
	last_stage = stage
	if not is_web():
		return
	_eval(stage_script(stage))

## The title screen is up: the shell can fade its loader away. Only the first
## call does anything, so returning to the menu later is free.
static func menu_ready() -> void:
	if _menu_reported:
		return
	_menu_reported = true
	if not is_web():
		return
	_eval(ready_script())

## The JavaScript that reports `stage` to the shell's `setStage` hook. Public
## and pure so the escaping can be unit-tested without a browser.
static func stage_script(stage: String) -> String:
	return "%s && %s.setStage(%s);" % [BRIDGE, BRIDGE, JSON.stringify(stage)]

## The JavaScript that tells the shell the title screen is up (its `ready` hook).
static func ready_script() -> String:
	return "%s && %s.ready();" % [BRIDGE, BRIDGE]

## Forget that the title screen was reported, so a fresh scene reports again.
static func reset() -> void:
	_menu_reported = false
	last_stage = ""

## Run `source` in the page's global context. The singleton is looked up by name
## rather than referenced directly: it only exists in the web build, and a
## desktop build must not fail to load this script over it.
static func _eval(source: String) -> void:
	var bridge := Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return
	bridge.eval(source, true)
