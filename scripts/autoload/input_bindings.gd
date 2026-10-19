extends Node
## InputBindings - the player's editable controls (autoload).
##
## Every rebindable course action is registered here with its default key or
## controller button, its label and the group it belongs to. The Settings
## screen's Controls page reads this registry, captures a new binding and calls
## assign_binding(); the game asks action_for_event() or matches() instead of
## comparing raw keycodes, and polling controls (camera pan, triggers) read the
## InputMap actions this node keeps up to date.
##
## Bindings are saved to the `controls` section of user://settings.cfg as a
## dictionary of action -> array of event descriptions, so they are a device
## preference rather than part of a save file. Only actions the player changed
## are stored: an action with no entry keeps its default, and Reset removes the
## entry. Mouse and touch controls are not rebindable and are left alone.
##
## Exact matching matters. Godot's InputMap ignores modifiers when matching an
## action that has none, so a plain S action would also fire on Ctrl+S. The
## dispatchers therefore call action_for_event(), which compares the modifiers
## as well as the key, and only the polling controls use Input.is_action_pressed.

## Emitted whenever one action's bindings change, including the other side of a
## conflict swap. Settings listens so two rows refresh together.
signal bindings_changed(action: String)
## Every action went back to its default (Reset All, or a reloaded file).
signal bindings_reset

const SETTINGS_SECTION := "controls"
const SETTINGS_KEY := "bindings"
const DEFAULT_SETTINGS_PATH := "user://settings.cfg"

## Order is the order the Settings rows and the F1 reference list show.
const GROUPS: Array[Dictionary] = [
	{
		"id": "camera",
		"title": "Camera",
		"description": "Move the camera, zoom and turn the view around the course.",
	},
	{
		"id": "game",
		"title": "Game & saving",
		"description": "Pause the clock, save and step through your course edits.",
	},
	{
		"id": "panels",
		"title": "Clubhouse panels",
		"description": "Open the clubhouse screens and the course overlays.",
	},
	{
		"id": "terrain",
		"title": "Terrain palette",
		"description": "Pick what the brush paints. Shift gives the harsher variants.",
	},
	{
		"id": "tools",
		"title": "Course tools",
		"description": "Place objects and switch the toolbar's tabs and elevation tools.",
	},
	{
		"id": "controller",
		"title": "Controller",
		"description": "Course controls for a gamepad. Menus keep the D-pad, A and B.",
	},
]

## Every rebindable action, in reading order. `defaults` holds the initial
## events; `mouse` entries are kept on Reset but are never captured or shown as
## the action's key.
const ACTIONS: Array[Dictionary] = [
	# --- Camera ------------------------------------------------------------
	{
		"action": "camera_pan_up", "group": "camera",
		"label": "Pan up", "hint": "The left stick and a middle-mouse drag also pan.",
		"defaults": [{"type": "key", "keycode": KEY_W}],
	},
	{
		"action": "camera_pan_down", "group": "camera",
		"label": "Pan down", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_S}],
	},
	{
		"action": "camera_pan_left", "group": "camera",
		"label": "Pan left", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_A}],
	},
	{
		"action": "camera_pan_right", "group": "camera",
		"label": "Pan right", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_D}],
	},
	{
		"action": "camera_zoom_in", "group": "camera",
		"label": "Zoom in", "hint": "The mouse wheel and a pinch always zoom too.",
		"defaults": [
			{"type": "key", "keycode": KEY_BRACKETRIGHT},
			{"type": "mouse", "button": MOUSE_BUTTON_WHEEL_UP},
		],
	},
	{
		"action": "camera_zoom_out", "group": "camera",
		"label": "Zoom out", "hint": "",
		"defaults": [
			{"type": "key", "keycode": KEY_BRACKETLEFT},
			{"type": "mouse", "button": MOUSE_BUTTON_WHEEL_DOWN},
		],
	},
	{
		"action": "rotate_camera", "group": "camera",
		"label": "Rotate view counter-clockwise", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_Q}],
	},
	{
		"action": "rotate_camera_cw", "group": "camera",
		"label": "Rotate view clockwise", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_Q, "shift": true}],
	},
	# --- Game and saving ---------------------------------------------------
	{
		"action": "pause_menu", "group": "game",
		"label": "Pause menu", "hint": "The controller's Start button always opens it.",
		"defaults": [
			{"type": "key", "keycode": KEY_P},
			{"type": "joy_button", "button": JOY_BUTTON_START},
		],
	},
	{
		"action": "simulation_pause", "group": "game",
		"label": "Pause / resume the clock", "hint": "A focused HUD control keeps Space for itself.",
		"defaults": [{"type": "key", "keycode": KEY_SPACE}],
	},
	{
		"action": "quick_save", "group": "game",
		"label": "Quick save", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_S, "ctrl": true}],
	},
	{
		"action": "undo", "group": "game",
		"label": "Undo", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_Z, "ctrl": true}],
	},
	{
		"action": "redo", "group": "game",
		"label": "Redo", "hint": "Ctrl + Y is also a default redo key.",
		"defaults": [
			{"type": "key", "keycode": KEY_Z, "ctrl": true, "shift": true},
			{"type": "key", "keycode": KEY_Y, "ctrl": true},
		],
	},
	{
		"action": "toggle_help", "group": "game",
		"label": "Controls help (F1)", "hint": "Opens this list anywhere in the game.",
		"defaults": [{"type": "key", "keycode": KEY_F1}],
	},
	# --- Clubhouse panels --------------------------------------------------
	{
		"action": "financial_overview", "group": "panels",
		"label": "Financial Overview", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_F}],
	},
	{
		"action": "marketing", "group": "panels",
		"label": "Marketing page", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_M}],
	},
	{
		"action": "tournaments", "group": "panels",
		"label": "Tournaments", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_U}],
	},
	{
		"action": "analytics", "group": "panels",
		"label": "Analytics", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_Z}],
	},
	{
		"action": "course_milestones", "group": "panels",
		"label": "Course Milestones", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_G}],
	},
	{
		"action": "world_milestones", "group": "panels",
		"label": "World Milestones", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_G, "shift": true}],
	},
	{
		"action": "achievements", "group": "panels",
		"label": "Achievements", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_T, "shift": true}],
	},
	{
		"action": "calendar", "group": "panels",
		"label": "Seasonal calendar", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_C}],
	},
	{
		"action": "event_feed", "group": "panels",
		"label": "Event feed", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_N}],
	},
	{
		"action": "course_scorecard", "group": "panels",
		"label": "Course scorecard", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_K}],
	},
	{
		"action": "course_map", "group": "panels",
		"label": "Course Map", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_M, "shift": true}],
	},
	{
		"action": "routing_overlay", "group": "panels",
		"label": "Routing overlay", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_R, "shift": true}],
	},
	{
		"action": "shot_heatmap", "group": "panels",
		"label": "Shot heatmap", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_V}],
	},
	{
		"action": "shot_heatmap_mode", "group": "panels",
		"label": "Cycle heatmap mode", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_V, "shift": true}],
	},
	{
		"action": "fairway_width_overlay", "group": "panels",
		"label": "Fairway width and carry overlay", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_J}],
	},
	{
		"action": "weather_debug", "group": "panels",
		"label": "Weather debug panel", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_F2}],
	},
	{
		"action": "terrain_debug", "group": "panels",
		"label": "Terrain debug overlay", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_F3}],
	},
	{
		"action": "season_debug", "group": "panels",
		"label": "Season debug panel", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_F4}],
	},
	# --- Terrain palette ---------------------------------------------------
	{
		"action": "terrain_fairway", "group": "terrain",
		"label": "Fairway", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_1}],
	},
	{
		"action": "terrain_rough", "group": "terrain",
		"label": "Rough", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_2}],
	},
	{
		"action": "terrain_green", "group": "terrain",
		"label": "Green", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_3}],
	},
	{
		"action": "terrain_tee", "group": "terrain",
		"label": "Tee box", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_4}],
	},
	{
		"action": "terrain_bunker", "group": "terrain",
		"label": "Bunker", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_5}],
	},
	{
		"action": "terrain_water", "group": "terrain",
		"label": "Water", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_6}],
	},
	{
		"action": "terrain_out_of_bounds", "group": "terrain",
		"label": "Out of bounds", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_7}],
	},
	{
		"action": "terrain_path", "group": "terrain",
		"label": "Walking path", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_8}],
	},
	{
		"action": "terrain_firm_fairway", "group": "terrain",
		"label": "Firm fairway", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_9}],
	},
	{
		"action": "terrain_waste_bunker", "group": "terrain",
		"label": "Waste bunker", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_0}],
	},
	{
		"action": "terrain_deep_rough", "group": "terrain",
		"label": "Deep rough", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_2, "shift": true}],
	},
	{
		"action": "terrain_pot_bunker", "group": "terrain",
		"label": "Pot bunker", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_5, "shift": true}],
	},
	{
		"action": "terrain_stream", "group": "terrain",
		"label": "Stream", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_6, "shift": true}],
	},
	{
		"action": "terrain_rocks", "group": "terrain",
		"label": "Rocks", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_7, "shift": true}],
	},
	{
		"action": "terrain_brush", "group": "terrain",
		"label": "Brush", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_8, "shift": true}],
	},
	{
		"action": "terrain_small_boulders", "group": "terrain",
		"label": "Small boulders", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_9, "shift": true}],
	},
	{
		"action": "terrain_large_boulders", "group": "terrain",
		"label": "Large boulders", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_0, "shift": true}],
	},
	{
		"action": "terrain_flowers", "group": "terrain",
		"label": "Wild flowers", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_F, "shift": true}],
	},
	# --- Course tools ------------------------------------------------------
	{
		"action": "tool_trees", "group": "tools",
		"label": "Tree tool", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_T}],
	},
	{
		"action": "tool_building", "group": "tools",
		"label": "Building tool", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_B}],
	},
	{
		"action": "tool_decoration", "group": "tools",
		"label": "Decoration tool", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_O}],
	},
	{
		"action": "tool_open_hole", "group": "tools",
		"label": "Open hole", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_H}],
	},
	{
		"action": "tool_bulldozer", "group": "tools",
		"label": "Bulldozer", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_X}],
	},
	{
		"action": "tab_terrain", "group": "tools",
		"label": "Course Terrain tab", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_EQUAL}],
	},
	{
		"action": "tab_improvements", "group": "tools",
		"label": "Improvements tab", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_PERIOD}],
	},
	{
		"action": "tab_elevation", "group": "tools",
		"label": "Elevations tab", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_E}],
	},
	{
		"action": "elevation_vertex", "group": "tools",
		"label": "Vertex elevation selector", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_V}],
	},
	{
		"action": "elevation_flat", "group": "tools",
		"label": "Flat square selector", "hint": "",
		"defaults": [{"type": "key", "keycode": KEY_EQUAL, "shift": true}],
	},
	{
		"action": "elevation_gradual", "group": "tools",
		"label": "Gradual square selector", "hint": "",
		"defaults": [
			{"type": "key", "keycode": KEY_MINUS},
			{"type": "key", "keycode": KEY_MINUS, "shift": true},
		],
	},
	# --- Controller --------------------------------------------------------
	{
		"action": "gamepad_rotate_ccw", "group": "controller",
		"label": "Rotate view counter-clockwise", "hint": "",
		"defaults": [{"type": "joy_button", "button": JOY_BUTTON_X}],
	},
	{
		"action": "gamepad_rotate_cw", "group": "controller",
		"label": "Rotate view clockwise", "hint": "",
		"defaults": [{"type": "joy_button", "button": JOY_BUTTON_Y}],
	},
	{
		"action": "gamepad_zoom_in", "group": "controller",
		"label": "Zoom in", "hint": "",
		"defaults": [{"type": "joy_motion", "axis": JOY_AXIS_TRIGGER_RIGHT, "value": 1.0}],
	},
	{
		"action": "gamepad_zoom_out", "group": "controller",
		"label": "Zoom out", "hint": "",
		"defaults": [{"type": "joy_motion", "axis": JOY_AXIS_TRIGGER_LEFT, "value": 1.0}],
	},
	{
		"action": "gamepad_focus_hud", "group": "controller",
		"label": "Focus the bottom-left dock", "hint": "",
		"defaults": [{"type": "joy_button", "button": JOY_BUTTON_BACK}],
	},
]

## Keys a binding may not steal: menus, focus navigation, the keyboard pointer
## and the two keys the capture uses itself.
const RESERVED_KEYCODES: Array[int] = [
	KEY_ESCAPE, KEY_TAB, KEY_ENTER, KEY_KP_ENTER, KEY_BACKSPACE, KEY_DELETE,
	KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT,
	KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK,
]
## Controller buttons that belong to menus and focus navigation.
const RESERVED_JOY_BUTTONS: Array[int] = [
	JOY_BUTTON_A, JOY_BUTTON_B,
	JOY_BUTTON_DPAD_UP, JOY_BUTTON_DPAD_DOWN, JOY_BUTTON_DPAD_LEFT, JOY_BUTTON_DPAD_RIGHT,
	JOY_BUTTON_LEFT_SHOULDER, JOY_BUTTON_RIGHT_SHOULDER,
]
## Sticks navigate focus and drive the pointer; triggers are free to rebind.
const RESERVED_JOY_AXES: Array[int] = [JOY_AXIS_LEFT_X, JOY_AXIS_LEFT_Y, JOY_AXIS_RIGHT_X, JOY_AXIS_RIGHT_Y]
const JOY_MOTION_CAPTURE_THRESHOLD := 0.6

## The file bindings are read from. A test may point this at a temporary file.
var settings_path: String = DEFAULT_SETTINGS_PATH

var _action_ids: Array[String] = []
var _info_by_action: Dictionary = {}
var _defaults: Dictionary = {}
var _overrides: Dictionary = {}


func _ready() -> void:
	if is_instance_valid(SaveManager):
		settings_path = SaveManager.SETTINGS_PATH
	_build_registry()
	for action in _action_ids:
		if not InputMap.has_action(action):
			InputMap.add_action(action)
	load_bindings()


# =============================================================================
# REGISTRY
# =============================================================================

func _build_registry() -> void:
	_action_ids.clear()
	_info_by_action.clear()
	_defaults.clear()
	for entry in ACTIONS:
		var action := str(entry.get("action", ""))
		if action.is_empty():
			continue
		_action_ids.append(action)
		_info_by_action[action] = entry
		var specs: Array[Dictionary] = []
		var raw_defaults: Array = entry.get("defaults", [])
		for raw in raw_defaults:
			if raw is Dictionary:
				specs.append((raw as Dictionary).duplicate(true))
		_defaults[action] = specs


## The group definitions, in display order.
func groups() -> Array[Dictionary]:
	return GROUPS


## The actions in one group, in display order.
func actions_in_group(group_id: String) -> Array[String]:
	var found: Array[String] = []
	for action in _action_ids:
		var info: Dictionary = _info_by_action[action]
		if str(info.get("group", "")) == group_id:
			found.append(action)
	return found


func has_action(action: String) -> bool:
	return _info_by_action.has(action)


func action_label(action: String) -> String:
	var info: Dictionary = _info_by_action.get(action, {})
	return str(info.get("label", action.capitalize()))


func action_hint(action: String) -> String:
	var info: Dictionary = _info_by_action.get(action, {})
	return str(info.get("hint", ""))


func group_title(group_id: String) -> String:
	for group in GROUPS:
		if str(group.get("id", "")) == group_id:
			return str(group.get("title", group_id.capitalize()))
	return group_id.capitalize()


func group_description(group_id: String) -> String:
	for group in GROUPS:
		if str(group.get("id", "")) == group_id:
			return str(group.get("description", ""))
	return ""


# =============================================================================
# BINDING STATE
# =============================================================================

## True when the player has changed this action from its default.
func is_customized(action: String) -> bool:
	return _overrides.has(action)


## The text a keycap shows: every editable event joined with " / ", or
## "Unbound". Mouse events are not shown because they cannot be edited.
func binding_text(action: String) -> String:
	var parts: Array[String] = []
	for spec in _current_editable_specs(action):
		var text := spec_text(spec)
		if not text.is_empty():
			parts.append(text)
	if parts.is_empty():
		return "Unbound"
	return " / ".join(parts)


## A human-readable name for one saved event description.
## The keycap text the action returns to on Reset, for tooltips and messages.
func default_binding_text(action: String) -> String:
	var parts: Array[String] = []
	for spec in _editable_default_specs(action):
		var text := spec_text(spec)
		if not text.is_empty():
			parts.append(text)
	if parts.is_empty():
		return "Unbound"
	return " / ".join(parts)


## True when at least one action differs from its default.
func has_custom_bindings() -> bool:
	return not _overrides.is_empty()


func spec_text(spec: Dictionary) -> String:
	match str(spec.get("type", "")):
		"key":
			return key_binding_text(spec)
		"joy_button":
			return joy_button_name(int(spec.get("button", -1)))
		"joy_motion":
			return joy_motion_name(int(spec.get("axis", -1)), float(spec.get("value", 1.0)))
		"mouse":
			return mouse_button_name(int(spec.get("button", -1)))
	return ""


static func key_binding_text(spec: Dictionary) -> String:
	var parts: Array[String] = []
	if bool(spec.get("ctrl", false)):
		parts.append("Ctrl")
	if bool(spec.get("shift", false)):
		parts.append("Shift")
	if bool(spec.get("alt", false)):
		parts.append("Alt")
	if bool(spec.get("meta", false)):
		parts.append("Meta")
	parts.append(key_display_name(int(spec.get("keycode", 0))))
	return " + ".join(parts)


static func key_display_name(keycode: int) -> String:
	match keycode:
		KEY_SPACE:
			return "Space"
		KEY_ESCAPE:
			return "Esc"
		KEY_TAB:
			return "Tab"
		KEY_ENTER, KEY_KP_ENTER:
			return "Enter"
		KEY_BRACKETLEFT:
			return "["
		KEY_BRACKETRIGHT:
			return "]"
		KEY_EQUAL:
			return "="
		KEY_MINUS:
			return "-"
		KEY_PERIOD:
			return "."
		KEY_COMMA:
			return ","
		KEY_SLASH:
			return "/"
		KEY_BACKSLASH:
			return "\\"
		KEY_SEMICOLON:
			return ";"
		KEY_APOSTROPHE:
			return "'"
		KEY_QUOTELEFT:
			return "`"
		KEY_BACKSPACE:
			return "Backspace"
		KEY_DELETE:
			return "Delete"
	var text := OS.get_keycode_string(keycode)
	if text.is_empty():
		return "Key %d" % keycode
	return text


static func joy_button_name(button: int) -> String:
	match button:
		JOY_BUTTON_A:
			return "A"
		JOY_BUTTON_B:
			return "B"
		JOY_BUTTON_X:
			return "X"
		JOY_BUTTON_Y:
			return "Y"
		JOY_BUTTON_LEFT_SHOULDER:
			return "LB"
		JOY_BUTTON_RIGHT_SHOULDER:
			return "RB"
		JOY_BUTTON_BACK:
			return "Back"
		JOY_BUTTON_START:
			return "Start"
		JOY_BUTTON_GUIDE:
			return "Guide"
		JOY_BUTTON_LEFT_STICK:
			return "L3"
		JOY_BUTTON_RIGHT_STICK:
			return "R3"
		JOY_BUTTON_DPAD_UP:
			return "D-pad Up"
		JOY_BUTTON_DPAD_DOWN:
			return "D-pad Down"
		JOY_BUTTON_DPAD_LEFT:
			return "D-pad Left"
		JOY_BUTTON_DPAD_RIGHT:
			return "D-pad Right"
	return "Button %d" % button


static func joy_motion_name(axis: int, value: float) -> String:
	match axis:
		JOY_AXIS_TRIGGER_LEFT:
			return "LT"
		JOY_AXIS_TRIGGER_RIGHT:
			return "RT"
		JOY_AXIS_LEFT_X:
			return "Left Stick →" if value > 0.0 else "Left Stick ←"
		JOY_AXIS_LEFT_Y:
			return "Left Stick ↓" if value > 0.0 else "Left Stick ↑"
		JOY_AXIS_RIGHT_X:
			return "Right Stick →" if value > 0.0 else "Right Stick ←"
		JOY_AXIS_RIGHT_Y:
			return "Right Stick ↓" if value > 0.0 else "Right Stick ↑"
	return "Axis %d" % axis


static func mouse_button_name(button: int) -> String:
	match button:
		MOUSE_BUTTON_LEFT:
			return "Left click"
		MOUSE_BUTTON_RIGHT:
			return "Right click"
		MOUSE_BUTTON_MIDDLE:
			return "Middle click"
		MOUSE_BUTTON_WHEEL_UP:
			return "Wheel up"
		MOUSE_BUTTON_WHEEL_DOWN:
			return "Wheel down"
	return "Mouse %d" % button


# =============================================================================
# EDITING
# =============================================================================

## Bind an event to an action. If another action already uses the same key or
## button it loses it, and a swap keeps both actions usable when it was the
## other action's only binding. Returns a dictionary:
##   { ok, reason, message, conflicts: Array[String], unchanged: bool }
func assign_binding(action: String, event: InputEvent) -> Dictionary:
	if not _defaults.has(action):
		return {"ok": false, "reason": "unknown", "message": "That control is not rebindable.", "conflicts": []}
	var reserved := reserved_reason(event)
	if not reserved.is_empty():
		return {"ok": false, "reason": "reserved", "message": reserved, "conflicts": []}
	var new_spec := _spec_from_event(event)
	if new_spec.is_empty():
		return {"ok": false, "reason": "invalid", "message": "Press a key or a controller button.", "conflicts": []}

	var current := _current_editable_specs(action)
	for spec in current:
		if _specs_equal(spec, new_spec):
			return {"ok": true, "reason": "", "message": "", "conflicts": [], "unchanged": true}

	var previous := _first_same_slot(current, new_spec)
	var target: Array[Dictionary] = []
	for spec in current:
		if not _same_slot(spec, new_spec):
			target.append(spec)
	target.append(new_spec)

	var conflicts: Array[String] = []
	var swapped := false
	for other in _action_ids:
		if other == action:
			continue
		var other_specs := _current_editable_specs(other)
		var kept: Array[Dictionary] = []
		var lost := false
		for spec in other_specs:
			if _specs_equal(spec, new_spec):
				lost = true
			else:
				kept.append(spec)
		if not lost:
			continue
		conflicts.append(other)
		if kept.is_empty() and not previous.is_empty() and conflicts.size() == 1:
			kept.append(previous)
			swapped = true
		_set_override(other, kept)
		_apply_action(other)

	_set_override(action, target)
	_apply_action(action)
	_save()
	bindings_changed.emit(action)
	for other in conflicts:
		bindings_changed.emit(other)
	return {
		"ok": true, "reason": "", "message": "", "conflicts": conflicts,
		"swapped": swapped, "unchanged": false,
	}


## Remove every editable binding from an action. It still has its fixed mouse
## controls (the wheel for zoom), but the keycap reads "Unbound" and Reset
## brings the defaults back.
func clear_binding(action: String) -> void:
	if not _defaults.has(action):
		return
	var none: Array[Dictionary] = []
	_set_override(action, none)
	_apply_action(action)
	_save()
	bindings_changed.emit(action)


## Put one action back on its defaults.
func reset_binding(action: String) -> void:
	if not _defaults.has(action):
		return
	_overrides.erase(action)
	_apply_action(action)
	_save()
	bindings_changed.emit(action)


## Put every action back on its defaults, and forget the saved overrides.
func reset_all(save: bool = true) -> void:
	_overrides.clear()
	_apply_all()
	if save:
		_save()
	bindings_reset.emit()


## Why a pressed key or button cannot be bound, or "" when it is allowed.
func reserved_reason(event: InputEvent) -> String:
	if event is InputEventKey:
		var key := event as InputEventKey
		var keycode := key.keycode if key.keycode != 0 else key.physical_keycode
		if keycode in RESERVED_KEYCODES:
			match keycode:
				KEY_ESCAPE:
					return "Esc is reserved for Back and Cancel."
				KEY_TAB:
					return "Tab is reserved for menus and the minimap."
				KEY_BACKSPACE, KEY_DELETE:
					return "Backspace and Delete unbind a control. Try another key."
				KEY_UP, KEY_DOWN, KEY_LEFT, KEY_RIGHT:
					return "Arrow keys are reserved for menus and the pointer."
				KEY_SHIFT, KEY_CTRL, KEY_ALT, KEY_META, KEY_CAPSLOCK, KEY_NUMLOCK, KEY_SCROLLLOCK:
					return "Hold Ctrl, Shift or Alt with another key."
				_:
					return "Enter is reserved for Select. Try another key."
		return ""
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if button.button_index in RESERVED_JOY_BUTTONS:
			return "%s is reserved for menus. Try another button." % joy_button_name(button.button_index)
		return ""
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < JOY_MOTION_CAPTURE_THRESHOLD:
			return "Press the button or trigger fully, then release it."
		if motion.axis in RESERVED_JOY_AXES:
			return "The sticks are reserved for navigation and the pointer. Use a trigger or a button."
		return ""
	return "Use a keyboard key or a controller button."


# =============================================================================
# EVENT MATCHING
# =============================================================================

## The action from `only` (or every registered action when empty) that this
## event triggers, or "". Key modifiers must match exactly, so Ctrl+S never
## fires a plain S binding. Key repeats and released keys never match.
func action_for_event(event: InputEvent, only: Array[String] = []) -> String:
	var candidates := _candidate_actions(only)
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return ""
		for action in candidates:
			for spec in _current_editable_specs(action):
				if str(spec.get("type", "")) == "key" and _spec_matches_key(spec, key):
					return action
		return ""
	if event is InputEventJoypadButton:
		var button := event as InputEventJoypadButton
		if not button.pressed:
			return ""
		for action in candidates:
			for spec in _current_editable_specs(action):
				if str(spec.get("type", "")) == "joy_button" \
						and int(spec.get("button", -1)) == button.button_index:
					return action
	return ""


## Whether this event is the binding for one action (see action_for_event).
func matches(event: InputEvent, action: String) -> bool:
	if not _defaults.has(action):
		return false
	return action_for_event(event, [action]) == action


## True while a trigger binding is held. Used by the camera's polling zoom.
func action_pressed(action: String) -> bool:
	return InputMap.has_action(action) and Input.is_action_pressed(action)


func _candidate_actions(only: Array[String]) -> Array[String]:
	if only.is_empty():
		return _action_ids
	var found: Array[String] = []
	for action in only:
		if _defaults.has(action):
			found.append(action)
	return found


static func _spec_matches_key(spec: Dictionary, event: InputEventKey) -> bool:
	var keycode := int(spec.get("keycode", 0))
	if keycode == 0:
		return false
	if event.keycode != keycode and event.physical_keycode != keycode:
		return false
	return event.ctrl_pressed == bool(spec.get("ctrl", false)) \
		and event.shift_pressed == bool(spec.get("shift", false)) \
		and event.alt_pressed == bool(spec.get("alt", false)) \
		and event.meta_pressed == bool(spec.get("meta", false))


# =============================================================================
# PERSISTENCE
# =============================================================================

## Read the settings file and put its overrides on top of the defaults. Public
## so a test (or a future Apply button) can re-read what is on disk.
func load_bindings() -> void:
	_overrides.clear()
	var config := ConfigFile.new()
	if config.load(settings_path) == OK:
		var saved: Variant = config.get_value(SETTINGS_SECTION, SETTINGS_KEY, {})
		if saved is Dictionary:
			var saved_map := saved as Dictionary
			for key in saved_map:
				var action := str(key)
				if not _defaults.has(action):
					continue
				var raw_specs: Variant = saved_map[key]
				if raw_specs is not Array:
					continue
				var raw_list := raw_specs as Array
				var specs: Array[Dictionary] = []
				for raw in raw_list:
					if raw is Dictionary:
						var spec := _sanitize_spec(raw as Dictionary)
						if not spec.is_empty():
							specs.append(spec)
				# An empty saved list is a deliberate Unbound; a list whose
				# entries were all malformed leaves the default in place.
				if raw_list.is_empty() or not specs.is_empty():
					_overrides[action] = specs
	_apply_all()
	bindings_reset.emit()


## A copy of the current overrides and path, for tests that must put the
## player's real bindings back afterwards (see tests/helpers/game_state.gd).
func capture_state() -> Dictionary:
	return {"path": settings_path, "overrides": _overrides.duplicate(true)}


func restore_state(state: Dictionary) -> void:
	settings_path = str(state.get("path", DEFAULT_SETTINGS_PATH))
	var saved: Variant = state.get("overrides", {})
	if saved is Dictionary:
		_overrides = (saved as Dictionary).duplicate(true)
	else:
		_overrides.clear()
	_apply_all()
	bindings_reset.emit()


func _save() -> void:
	var config := ConfigFile.new()
	config.load(settings_path)
	config.set_value(SETTINGS_SECTION, SETTINGS_KEY, _overrides)
	config.save(settings_path)


# =============================================================================
# INPUTMAP
# =============================================================================

func _apply_all() -> void:
	for action in _action_ids:
		_apply_action(action)


func _apply_action(action: String) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	InputMap.action_erase_events(action)
	for spec in _current_specs(action):
		var event := _event_from_spec(spec)
		if event != null:
			InputMap.action_add_event(action, event)


func _current_specs(action: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not _overrides.has(action):
		for spec in _editable_default_specs(action):
			result.append(spec)
		for spec in _fixed_default_specs(action):
			result.append(spec)
		return result
	for spec in _fixed_default_specs(action):
		result.append(spec)
	for spec in _current_editable_specs(action):
		result.append(spec)
	return result


func _current_editable_specs(action: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if _overrides.has(action):
		var raw: Variant = _overrides[action]
		if raw is Array:
			for spec in (raw as Array):
				if spec is Dictionary:
					result.append((spec as Dictionary).duplicate(true))
		return result
	return _editable_default_specs(action)


func _editable_default_specs(action: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = _defaults.get(action, [])
	if raw is Array:
		for spec in (raw as Array):
			if spec is Dictionary and str((spec as Dictionary).get("type", "")) != "mouse":
				result.append((spec as Dictionary).duplicate(true))
	return result


func _fixed_default_specs(action: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = _defaults.get(action, [])
	if raw is Array:
		for spec in (raw as Array):
			if spec is Dictionary and str((spec as Dictionary).get("type", "")) == "mouse":
				result.append((spec as Dictionary).duplicate(true))
	return result


func _set_override(action: String, specs: Array[Dictionary]) -> void:
	if _same_spec_list(specs, _editable_default_specs(action)):
		_overrides.erase(action)
	else:
		var stored: Array[Dictionary] = []
		for spec in specs:
			stored.append(spec.duplicate(true))
		_overrides[action] = stored


func _spec_from_event(event: InputEvent) -> Dictionary:
	if event is InputEventKey:
		var key := event as InputEventKey
		var keycode := key.keycode if key.keycode != 0 else key.physical_keycode
		if keycode == 0:
			return {}
		return {
			"type": "key", "keycode": keycode,
			"ctrl": key.ctrl_pressed, "shift": key.shift_pressed,
			"alt": key.alt_pressed, "meta": key.meta_pressed,
		}
	if event is InputEventJoypadButton:
		return {"type": "joy_button", "button": int((event as InputEventJoypadButton).button_index)}
	if event is InputEventJoypadMotion:
		var motion := event as InputEventJoypadMotion
		if absf(motion.axis_value) < JOY_MOTION_CAPTURE_THRESHOLD:
			return {}
		return {
			"type": "joy_motion", "axis": int(motion.axis),
			"value": 1.0 if motion.axis_value > 0.0 else -1.0,
		}
	return {}


func _event_from_spec(spec: Dictionary) -> InputEvent:
	match str(spec.get("type", "")):
		"key":
			var key := InputEventKey.new()
			key.keycode = int(spec.get("keycode", 0)) as Key
			key.ctrl_pressed = bool(spec.get("ctrl", false))
			key.shift_pressed = bool(spec.get("shift", false))
			key.alt_pressed = bool(spec.get("alt", false))
			key.meta_pressed = bool(spec.get("meta", false))
			return key
		"joy_button":
			var button := InputEventJoypadButton.new()
			button.button_index = int(spec.get("button", 0)) as JoyButton
			return button
		"joy_motion":
			var motion := InputEventJoypadMotion.new()
			motion.axis = int(spec.get("axis", 0)) as JoyAxis
			motion.axis_value = float(spec.get("value", 1.0))
			return motion
		"mouse":
			var mouse := InputEventMouseButton.new()
			mouse.button_index = int(spec.get("button", 0)) as MouseButton
			return mouse
	return null


func _sanitize_spec(raw: Dictionary) -> Dictionary:
	match str(raw.get("type", "")):
		"key":
			var keycode := int(raw.get("keycode", 0))
			if keycode == 0:
				return {}
			return {
				"type": "key", "keycode": keycode,
				"ctrl": bool(raw.get("ctrl", false)), "shift": bool(raw.get("shift", false)),
				"alt": bool(raw.get("alt", false)), "meta": bool(raw.get("meta", false)),
			}
		"joy_button":
			return {"type": "joy_button", "button": int(raw.get("button", 0))}
		"joy_motion":
			return {
				"type": "joy_motion", "axis": int(raw.get("axis", 0)),
				"value": 1.0 if float(raw.get("value", 1.0)) >= 0.0 else -1.0,
			}
		"mouse":
			return {"type": "mouse", "button": int(raw.get("button", 0))}
	return {}


static func _same_slot(a: Dictionary, b: Dictionary) -> bool:
	var a_type := str(a.get("type", ""))
	var b_type := str(b.get("type", ""))
	if a_type != b_type:
		return false
	return a_type != "mouse"


static func _first_same_slot(specs: Array[Dictionary], target: Dictionary) -> Dictionary:
	for spec in specs:
		if _same_slot(spec, target):
			return spec.duplicate(true)
	return {}


static func _specs_equal(a: Dictionary, b: Dictionary) -> bool:
	if str(a.get("type", "")) != str(b.get("type", "")):
		return false
	match str(a.get("type", "")):
		"key":
			return int(a.get("keycode", 0)) == int(b.get("keycode", 0)) \
				and bool(a.get("ctrl", false)) == bool(b.get("ctrl", false)) \
				and bool(a.get("shift", false)) == bool(b.get("shift", false)) \
				and bool(a.get("alt", false)) == bool(b.get("alt", false)) \
				and bool(a.get("meta", false)) == bool(b.get("meta", false))
		"joy_button", "mouse":
			return int(a.get("button", -1)) == int(b.get("button", -2))
		"joy_motion":
			return int(a.get("axis", -1)) == int(b.get("axis", -2)) \
				and signf(float(a.get("value", 0.0))) == signf(float(b.get("value", 0.0)))
	return false


static func _same_spec_list(a: Array[Dictionary], b: Array[Dictionary]) -> bool:
	if a.size() != b.size():
		return false
	for index in a.size():
		if not _specs_equal(a[index], b[index]):
			return false
	return true
