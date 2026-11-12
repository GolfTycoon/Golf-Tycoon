extends RefCounted
class_name GuiTheme
## GuiTheme - One complete design for the game's interface, as data.
##
## A GUI theme is a palette (named colours, "roles"), a handful of
## metrics (corner radii, border width, base font size, shadow size,
## background opacities), up to two typefaces, and targeted "rules" that
## aim a style at one screen, one control type or one named control.
## Mods ship one as JSON - the `gui_theme` content key in mod.json, see
## docs/modding/gui-themes.md - and the ContentRegistry loads its font
## and icon files, then hands the winning one to the main scene, which
## activates it before the HUD is built:
##
##   * GuiTheme.build_theme() becomes the HUD root's Theme, so every
##     control that takes its look from the Theme (most buttons, labels,
##     panels, fields, menus, scrollbars) is dressed by it directly;
##   * GuiThemeApplier walks the live control tree and re-maps the
##     code-built StyleBoxFlat / colour overrides that match the stock
##     palette onto the theme's roles, swaps the game's stock typefaces
##     for the theme's, applies the targeted rules, and keeps doing so
##     for panels and popups created later;
##   * PixelButtonStyle asks remap_color() while painting its generated
##     glass-pill frames, so the menu cards follow too - as do the
##     bottom bar's painted turf fans (the bottom_bar roles).
##
## Anything a theme leaves out keeps the stock value, so a mod can change
## three colours and still dress the whole interface coherently. The stock
## values below mirror assets/themes/game_theme.tres, UIConstants and
## MenuStyle - test_gui_theme.gd pins the shared ones to the .tres so the
## two cannot drift apart silently.
##
## This class is deliberately autoload-free (like ModManifest): parsing a
## theme must work in unit tests and command-line tools, not just in a
## running game. The only game-wide state is the static "active" theme,
## set by the main scene (and cleared on the way out).

# =============================================================================
# THE STOCK PALETTE (what the unmodded game looks like)
# =============================================================================

## Colour roles a theme may set, with their stock values. The sources:
## game_theme.tres (Button / PanelContainer / scrollbar styles), UIConstants
## (COLOR_*), MenuStyle (CARD_* / INSET_BG / INK).
static func default_colors() -> Dictionary:
	return {
		"panel": Color(0.094, 0.184, 0.161, 0.98),
		"inset": Color(0.020, 0.051, 0.039, 0.92),
		"deep": Color("10241f"),
		"button": Color(0.157, 0.263, 0.212, 0.96),
		"button_hover": Color(0.196, 0.325, 0.255, 1.0),
		"button_pressed": Color(0.106, 0.200, 0.157, 1.0),
		"button_disabled": Color(0.059, 0.110, 0.090, 0.72),
		"primary": Color("365c43"),
		"primary_hover": Color("476f50"),
		"border": Color(0.5, 0.62, 0.52, 0.8),
		"focus": Color(1.0, 0.965, 0.863, 1.0),
		"scrollbar": Color(0.3, 0.3, 0.3, 1.0),
		"scrollbar_hover": Color(0.4, 0.4, 0.4, 1.0),
		"text": Color("f4edd9"),
		"text_dim": Color("b9c7af"),
		"text_muted": Color("7e9184"),
		"accent": Color("e5c57c"),
		"accent_text": Color("10241f"),
		"success": Color(0.4, 0.9, 0.4),
		"warning": Color(0.9, 0.9, 0.4),
		"danger": Color(0.9, 0.4, 0.4),
		"info": Color(0.4, 0.7, 1.0),
		"tooltip": Color(0.07, 0.07, 0.07, 0.98),
		"bottom_bar": Color("10241a"),
		"bottom_bar_light": Color("173423"),
		"bottom_bar_socket": Color("0a1811"),
	}

## Metric roles a theme may set, with their stock values (game_theme.tres
## corner radii and shadows, UIConstants.FONT_SIZE_BASE).
static func default_metrics() -> Dictionary:
	return {
		"panel_radius": 16,
		"button_radius": 14,
		"border_width": 1,
		"font_size": 14,
		"shadow_size": 6,
	}

## Stock colour -> role pairs, for re-mapping code-built overrides (see
## GuiThemeApplier and PixelButtonStyle). A list, not a dictionary: one
## stock grey (0.4, 0.4, 0.4) is both the theme file's disabled-text colour
## and its scrollbar grip, and the text reading wins by coming first.
## Matching is two-phase: an exact colour (alpha included) wins first;
## failing that, the first entry whose RGB matches takes it, so a
## translucent cousin of a known fill still lands on the right role and
## only its alpha is preserved. List order is the priority within each
## phase, so panel fills precede the disabled button fill that shares
## their RGB.
static func stock_color_roles() -> Array:
	return [
		[Color(0.094, 0.184, 0.161, 0.98), "panel"],
		[Color("182f29f5"), "panel"],
		[Color(0.043, 0.098, 0.078, 0.88), "panel"],
		[Color(0.031, 0.071, 0.059, 0.88), "panel"],
		[Color(0.031, 0.071, 0.059, 0.72), "panel"],
		[Color(0.157, 0.263, 0.212, 0.96), "button"],
		[Color("294238"), "button"],
		[Color(0.196, 0.325, 0.255, 1.0), "button_hover"],
		[Color("365346"), "button_hover"],
		[Color(0.086, 0.180, 0.141, 0.95), "button_hover"],
		[Color(0.106, 0.200, 0.157, 1.0), "button_pressed"],
		[Color(0.027, 0.063, 0.051, 0.97), "button_pressed"],
		[Color("203e30"), "button_pressed"],
		[Color(0.043, 0.098, 0.078, 0.55), "button_disabled"],
		[Color(0.059, 0.110, 0.090, 0.72), "button_disabled"],
		[Color(0.020, 0.051, 0.039, 0.92), "inset"],
		[Color("10241f"), "deep"],
		[Color("08130f"), "deep"],
		[Color(0.008, 0.043, 0.031, 1.0), "deep"],
		[Color("365c43"), "primary"],
		[Color("476f50"), "primary_hover"],
		[Color("7fb08a"), "primary"],
		[Color("63715a"), "border"],
		[Color(0.5, 0.62, 0.52, 0.8), "border"],
		[Color(0.39, 0.44, 0.35, 0.7), "border"],
		[Color(0.45, 0.5, 0.42, 0.8), "border"],
		[Color("6d8a76"), "border"],
		[Color(1.0, 0.965, 0.863, 1.0), "focus"],
		[Color(1.0, 0.96, 0.84, 0.14), "focus"],
		[Color("f4edd9"), "text"],
		[Color("e7f3d6"), "text"],
		[Color("b9c7af"), "text_dim"],
		[Color("7e9184"), "text_muted"],
		[Color(0.4, 0.4, 0.4, 1.0), "text_muted"],
		[Color("e5c57c"), "accent"],
		[Color(0.4, 0.9, 0.4, 1.0), "success"],
		[Color(0.9, 0.9, 0.4, 1.0), "warning"],
		[Color(0.9, 0.4, 0.4, 1.0), "danger"],
		[Color(0.4, 0.7, 1.0, 1.0), "info"],
		[Color(0.3, 0.3, 0.3, 1.0), "scrollbar"],
		[Color(0.4, 0.4, 0.4, 1.0), "scrollbar_hover"],
		[Color(0.07, 0.07, 0.07, 0.98), "tooltip"],
		[Color("10241a"), "bottom_bar"],
		[Color("173423"), "bottom_bar_light"],
		[Color("0a1811"), "bottom_bar_socket"],
		[Color("081812"), "deep"],
		[Color("e5bd66"), "accent"],
	]

const _METRIC_RANGES: Dictionary = {
	"panel_radius": [0, 32],
	"button_radius": [0, 32],
	"border_width": [0, 4],
	"font_size": [10, 20],
	"shadow_size": [0, 16],
}

## Fractional metrics, stored apart from the integer ones above: how solid
## the panel and button backgrounds are (1 = the stock fully-painted look,
## lower = glass over the course). Set like any other metric.
const _FLOAT_METRIC_RANGES: Dictionary = {
	"button_opacity": [0.0, 1.0],
	"panel_opacity": [0.0, 1.0],
}

## The selectors a rule's `target` may name. Every key given must match:
## `screen` is a named ancestor (the screen the control lives on - MainMenu,
## ModsScreen, HUD, ...), `type` an engine or script class (Button, Label,
## PixelCircleButton, ...), `name` the control's own node name.
const RULE_TARGET_KEYS: Array[String] = ["screen", "type", "name"]

## Colour properties a rule may set, in the rule's own vocabulary (the
## applier translates them onto whatever the targeted control wears).
const RULE_COLOR_KEYS: Array[String] = [
	"background", "background_hover", "background_pressed",
	"background_disabled", "border", "text",
]

## Number properties a rule may set, with their clamps.
const RULE_INT_RANGES: Dictionary = {
	"radius": [0, 32],
	"border_width": [0, 4],
	"shadow_size": [0, 16],
	"font_size": [8, 40],
}

# =============================================================================
# ONE PARSED THEME
# =============================================================================

var theme_name: String = ""
var description: String = ""
## Problems found while parsing, in player-readable words. A theme with
## warnings still applies - the offending entries keep their stock values.
var warnings: Array[String] = []

var _colors: Dictionary = {}
var _metrics: Dictionary = {}
var _float_metrics: Dictionary = {"button_opacity": 1.0, "panel_opacity": 1.0}

## Typefaces the design wears, once the registry has loaded the files the
## palette named (font_path / font_bold_path below, kept as written for
## to_dictionary and error messages). Script mods may hand over Font
## resources directly; then the paths stay empty. `font` dresses body text,
## `font_bold` the headings and buttons that wear the game's display fonts.
var font: Font = null
var font_bold: Font = null
var font_path: String = ""
var font_bold_path: String = ""

## Targeted rules (see _parse_rule): normalised dictionaries in palette
## order, each {"target": {...}, "specificity": int, ...style properties}.
## The ContentRegistry resolves their font/icon paths into resources in
## place; style_for() merges what matches a control.
var rules: Array[Dictionary] = []


func _init() -> void:
	_colors = default_colors()
	_metrics = default_metrics()


## The stock design, untouched - also what "no GUI theme mod" means.
static func stock() -> GuiTheme:
	return GuiTheme.new()


## Parse a theme from its JSON shape:
##   { "name": "...", "description": "...",
##     "colors": { "panel": "16222ecc", ... },
##     "metrics": { "panel_radius": 20, ... } }
## Colours are hex strings (RRGGBB or RRGGBBAA, optional '#') or
## [r, g, b, a] arrays. Missing entries keep the stock value; a button
## family left half-specified is completed from the themed base colour
## (hover lifts, pressed sinks, disabled fades), so restyling the buttons
## takes one line, not four.
static func from_dictionary(data: Dictionary) -> GuiTheme:
	var theme := GuiTheme.new()
	theme.theme_name = str(data.get("name", "")).strip_edges()
	theme.description = str(data.get("description", "")).strip_edges()

	var explicit: Dictionary = {}
	var raw_colors: Variant = data.get("colors", {})
	if raw_colors is Dictionary:
		for role in raw_colors:
			var role_name := str(role)
			if not theme._colors.has(role_name):
				theme.warnings.append("Unknown colour '%s' - it was ignored. See docs/modding/gui-themes.md for the role list." % role_name)
				continue
			var parsed: Variant = _parse_color(raw_colors[role])
			if parsed == null:
				theme.warnings.append("Colour '%s' is not a hex string like \"8be9e2\" or an [r, g, b, a] array; the stock colour was kept." % role_name)
				continue
			theme._colors[role_name] = parsed
			explicit[role_name] = true
	elif data.has("colors"):
		theme.warnings.append("'colors' must be an object of role -> colour; the stock palette was kept.")

	var raw_metrics: Variant = data.get("metrics", {})
	if raw_metrics is Dictionary:
		for key in raw_metrics:
			var metric_name := str(key)
			var value: Variant = raw_metrics[key]
			if _FLOAT_METRIC_RANGES.has(metric_name):
				if not (value is int or value is float):
					theme.warnings.append("Metric '%s' must be a number; the stock value was kept." % metric_name)
					continue
				var float_range: Array = _FLOAT_METRIC_RANGES[metric_name]
				theme._float_metrics[metric_name] = clampf(float(value),
					float(float_range[0]), float(float_range[1]))
				continue
			if not theme._metrics.has(metric_name):
				theme.warnings.append("Unknown metric '%s' - it was ignored." % metric_name)
				continue
			if not (value is int or value is float):
				theme.warnings.append("Metric '%s' must be a number; the stock value was kept." % metric_name)
				continue
			var range_pair: Array = _METRIC_RANGES[metric_name]
			theme._metrics[metric_name] = clampi(int(round(float(value))),
				int(range_pair[0]), int(range_pair[1]))
	elif data.has("metrics"):
		theme.warnings.append("'metrics' must be an object of metric -> number; the stock values were kept.")

	for slot in ["font", "font_bold"]:
		if not data.has(slot):
			continue
		var font_value: Variant = data[slot]
		if font_value is Font:
			if slot == "font":
				theme.font = font_value as Font
			else:
				theme.font_bold = font_value as Font
		elif font_value is String and not str(font_value).strip_edges().is_empty():
			if slot == "font":
				theme.font_path = str(font_value).strip_edges()
			else:
				theme.font_bold_path = str(font_value).strip_edges()
		else:
			theme.warnings.append("'%s' must be a font file in your mod folder (a .ttf or .otf path); it was ignored." % slot)

	_parse_rules(theme, data.get("rules", []), data.has("rules"))

	_derive_states(theme, explicit)
	return theme


## Parse the `rules` list: targeted styles for one part of the interface.
## Each rule is {"target": {screen/type/name}, ...style properties} - see
## RULE_COLOR_KEYS / RULE_INT_RANGES, plus `opacity` (0-1), `font` and
## `icon` (a Font/Texture2D from code, or a file path the registry loads)
## and `glyph` (a PixelCircleButton pictogram name). Bad entries warn once
## and are skipped; a rule with nothing valid to say is dropped.
static func _parse_rules(theme: GuiTheme, raw_rules: Variant, present: bool) -> void:
	if present and not (raw_rules is Array):
		theme.warnings.append("'rules' must be a list of rule objects; they were ignored.")
		return
	for entry in raw_rules:
		if not (entry is Dictionary):
			theme.warnings.append("A rule that is not an object was skipped.")
			continue
		var rule := _parse_rule(theme, entry)
		if not rule.is_empty():
			theme.rules.append(rule)


static func _parse_rule(theme: GuiTheme, entry: Dictionary) -> Dictionary:
	var known: Array[String] = ["target", "opacity", "font", "icon", "glyph"]
	known.append_array(RULE_COLOR_KEYS)
	for key in RULE_INT_RANGES:
		known.append(str(key))
	var unknown: Array[String] = []
	for key in entry:
		if not known.has(str(key)):
			unknown.append(str(key))
	if not unknown.is_empty():
		theme.warnings.append("A rule names unknown propert%s %s - %s ignored. See docs/modding/gui-themes.md for the rule style list." % [
			"y" if unknown.size() == 1 else "ies", ", ".join(unknown),
			"it was" if unknown.size() == 1 else "they were"])
	var raw_target: Variant = entry.get("target", {})
	if not (raw_target is Dictionary) or (raw_target as Dictionary).is_empty():
		theme.warnings.append("A rule without a 'target' object (screen, type and/or name) was skipped.")
		return {}
	var target: Dictionary = {}
	for key in raw_target:
		var target_key := str(key)
		var target_value := str(raw_target[key]).strip_edges()
		if not RULE_TARGET_KEYS.has(target_key) or target_value.is_empty():
			theme.warnings.append("A rule's target may only name screen, type and/or name; '%s' was ignored." % target_key)
			continue
		target[target_key] = target_value
	if target.is_empty():
		theme.warnings.append("A rule whose target names nothing was skipped.")
		return {}
	var rule: Dictionary = {"target": target, "specificity":
		(4 if target.has("name") else 0) + (2 if target.has("screen") else 0)
		+ (1 if target.has("type") else 0)}
	var styled := false
	for color_key in RULE_COLOR_KEYS:
		if not entry.has(color_key):
			continue
		var parsed_color: Variant = _parse_color(entry[color_key])
		if parsed_color == null:
			theme.warnings.append("A rule's '%s' is not a hex colour or [r, g, b, a] array; it was ignored." % color_key)
			continue
		rule[color_key] = parsed_color
		styled = true
	for int_key in RULE_INT_RANGES:
		if not entry.has(int_key):
			continue
		var int_value: Variant = entry[int_key]
		if not (int_value is int or int_value is float):
			theme.warnings.append("A rule's '%s' must be a number; it was ignored." % int_key)
			continue
		var int_range: Array = RULE_INT_RANGES[int_key]
		rule[int_key] = clampi(int(round(float(int_value))), int(int_range[0]), int(int_range[1]))
		styled = true
	if entry.has("opacity"):
		var opacity_value: Variant = entry["opacity"]
		if opacity_value is int or opacity_value is float:
			rule["opacity"] = clampf(float(opacity_value), 0.0, 1.0)
			styled = true
		else:
			theme.warnings.append("A rule's 'opacity' must be a number from 0 to 1; it was ignored.")
	if entry.has("font"):
		var rule_font: Variant = entry["font"]
		if rule_font is Font:
			rule["font"] = rule_font
			styled = true
		elif rule_font is String and not str(rule_font).strip_edges().is_empty():
			rule["font_path"] = str(rule_font).strip_edges()
			styled = true
		else:
			theme.warnings.append("A rule's 'font' must be a font file path; it was ignored.")
	if entry.has("icon"):
		var rule_icon: Variant = entry["icon"]
		if rule_icon is Texture2D:
			rule["icon"] = rule_icon
			styled = true
		elif rule_icon is String and not str(rule_icon).strip_edges().is_empty():
			rule["icon_path"] = str(rule_icon).strip_edges()
			styled = true
		else:
			theme.warnings.append("A rule's 'icon' must be an image file path (a .png in your mod folder); it was ignored.")
	if entry.has("glyph"):
		var glyph_name := str(entry["glyph"]).strip_edges()
		if PixelCircleButton.ICONS.has(glyph_name):
			rule["glyph"] = glyph_name
			styled = true
		else:
			theme.warnings.append("A rule's glyph '%s' is not one of the medallion pictograms; it was ignored. See docs/modding/gui-themes.md for the list." % glyph_name)
	if not styled:
		theme.warnings.append("A rule targeting %s styles nothing and was skipped." % str(target))
		return {}
	return rule


## Complete a half-specified button family from its themed base, the way
## the stock palette relates its own states.
static func _derive_states(theme: GuiTheme, explicit: Dictionary) -> void:
	if explicit.has("button"):
		var states := derived_button_states(theme._colors["button"])
		for state in ["button_hover", "button_pressed", "button_disabled"]:
			if not explicit.has(state):
				theme._colors[state] = states[state]
	if explicit.has("primary") and not explicit.has("primary_hover"):
		var primary: Color = theme._colors["primary"]
		theme._colors["primary_hover"] = primary.lightened(0.12)
	if explicit.has("scrollbar") and not explicit.has("scrollbar_hover"):
		var bar: Color = theme._colors["scrollbar"]
		theme._colors["scrollbar_hover"] = bar.lightened(0.18)
	# The bottom bar's fan is mown in two turf tones with darker sockets;
	# setting the one `bottom_bar` colour derives its companions the way
	# the stock constants relate (light ≈ ×1.42, socket ≈ ×0.65).
	if explicit.has("bottom_bar"):
		var turf: Color = theme._colors["bottom_bar"]
		if not explicit.has("bottom_bar_light"):
			theme._colors["bottom_bar_light"] = _scaled(turf, 1.42)
		if not explicit.has("bottom_bar_socket"):
			theme._colors["bottom_bar_socket"] = _scaled(turf, 0.65)


## The hover/pressed/disabled family a button base colour implies, the
## way the stock palette relates its own states (hover lifts, pressed
## sinks, disabled fades toward grey). GuiThemeApplier uses the same
## family when a rule names only a button's `background`.
static func derived_button_states(base: Color) -> Dictionary:
	var faded := base.lerp(Color(base.get_luminance(), base.get_luminance(),
		base.get_luminance(), base.a), 0.5)
	faded.a = base.a * 0.65
	return {
		"button_hover": Color(base.lightened(0.12).r, base.lightened(0.12).g,
			base.lightened(0.12).b, base.a),
		"button_pressed": Color(base.darkened(0.15).r, base.darkened(0.15).g,
			base.darkened(0.15).b, minf(base.a + 0.08, 1.0)),
		"button_disabled": faded,
	}


## Multiply a colour's light without shifting its hue (unlike lightened,
## which walks toward white): the bottom fan's turf steps, kept in family.
static func _scaled(base: Color, factor: float) -> Color:
	return Color(minf(base.r * factor, 1.0), minf(base.g * factor, 1.0),
		minf(base.b * factor, 1.0), base.a)


static func _parse_color(value: Variant) -> Variant:
	if value is String:
		var text := str(value).strip_edges().trim_prefix("#")
		if Color.html_is_valid(text):
			return Color.html(text)
		# Godot's named colours ("white", "gold") are welcome too.
		var named := Color.from_string(text.to_lower(), Color(0, 0, 0, -1.0))
		if named.a >= 0.0:
			return named
		return null
	if value is Array and (value as Array).size() in [3, 4]:
		var parts: Array = value
		for part in parts:
			if not (part is int or part is float):
				return null
		return Color(clampf(float(parts[0]), 0.0, 1.0), clampf(float(parts[1]), 0.0, 1.0),
			clampf(float(parts[2]), 0.0, 1.0),
			clampf(float(parts[3]), 0.0, 1.0) if parts.size() == 4 else 1.0)
	return null


func color(role: String) -> Color:
	return _colors.get(role, Color.MAGENTA)


func metric(key: String) -> int:
	return int(_metrics.get(key, 0))


## A fractional metric (button_opacity / panel_opacity), 1.0 when unset.
func metricf(key: String) -> float:
	return float(_float_metrics.get(key, 1.0))


## The merged style every rule matching one control asks for, or {} when
## none do. Rules merge property by property: a property comes from the
## most specific matching rule that sets it (name outweighs screen
## outweighs type), and between equals the later rule in the file wins -
## so a broad screen rule and one named-button exception compose instead
## of fighting. `type_names` is the control's engine class plus its script
## class; `ancestor_names` its own name and every ancestor's, screen last.
func style_for(control_name: String, type_names: Array, ancestor_names: Array) -> Dictionary:
	var merged: Dictionary = {}
	var best: Dictionary = {}
	for rule in rules:
		if not _rule_matches(rule["target"], control_name, type_names, ancestor_names):
			continue
		var specificity := int(rule["specificity"])
		for key in rule:
			if key in ["target", "specificity", "font_path", "icon_path"]:
				continue
			if (key == "font" and rule["font"] == null) \
					or (key == "icon" and rule["icon"] == null):
				continue
			if int(best.get(key, -1)) > specificity:
				continue
			best[key] = specificity
			merged[key] = rule[key]
	return merged


static func _rule_matches(target: Dictionary, control_name: String,
		type_names: Array, ancestor_names: Array) -> bool:
	if target.has("name") and str(target["name"]) != control_name:
		return false
	if target.has("type") and not type_names.has(str(target["type"])):
		return false
	if target.has("screen") and not ancestor_names.has(str(target["screen"])):
		return false
	return true


## The theme as plain JSON-shaped data (colours back to hex), the form the
## registry keeps and tests compare.
func to_dictionary() -> Dictionary:
	var colors: Dictionary = {}
	for role in _colors:
		colors[role] = (_colors[role] as Color).to_html()
	var metrics: Dictionary = _metrics.duplicate()
	for key in _float_metrics:
		metrics[key] = _float_metrics[key]
	var serialised_rules: Array = []
	for rule in rules:
		var entry: Dictionary = {"target": (rule["target"] as Dictionary).duplicate()}
		for key in rule:
			if key in ["target", "specificity", "font", "icon"]:
				continue
			entry[key] = (rule[key] as Color).to_html() if rule[key] is Color else rule[key]
		serialised_rules.append(entry)
	var data: Dictionary = {
		"name": theme_name,
		"description": description,
		"colors": colors,
		"metrics": metrics,
		"rules": serialised_rules,
	}
	if not font_path.is_empty():
		data["font"] = font_path
	if not font_bold_path.is_empty():
		data["font_bold"] = font_bold_path
	return data


# =============================================================================
# RE-MAPPING STOCK COLOURS ONTO THIS THEME
# =============================================================================

## The role a stock colour belongs to, or "" when this palette never uses
## it (semantic one-offs - a score's gold, a golfer's shirt - stay put).
func role_for(stock_color: Color) -> String:
	var pairs := stock_color_roles()
	for pair in pairs:
		if _same_color(stock_color, (pair as Array)[0] as Color):
			return str((pair as Array)[1])
	for pair in pairs:
		var known_color := (pair as Array)[0] as Color
		if absf(stock_color.r - known_color.r) < 0.01 \
				and absf(stock_color.g - known_color.g) < 0.01 \
				and absf(stock_color.b - known_color.b) < 0.01:
			return str((pair as Array)[1])
	return ""


## A stock colour re-dressed in this theme. The alpha travels in
## proportion to the role's stock alpha, so a 72%-opaque rail over a
## 98%-opaque panel stays the more translucent of the two. Unmapped
## colours come back unchanged.
func map_color(stock_color: Color) -> Color:
	var role := role_for(stock_color)
	if role.is_empty():
		return stock_color
	var themed := color(role)
	var stock_role: Color = default_colors()[role]
	if stock_role.a > 0.001:
		themed.a = clampf(themed.a * stock_color.a / stock_role.a, 0.0, 1.0)
	return themed


static func _same_color(a: Color, b: Color) -> bool:
	return absf(a.r - b.r) < 0.004 and absf(a.g - b.g) < 0.004 \
		and absf(a.b - b.b) < 0.004 and absf(a.a - b.a) < 0.004


# =============================================================================
# THE ACTIVE THEME (set by the main scene before the HUD is built)
# =============================================================================

static var _active: GuiTheme = null


static func activate(theme: GuiTheme) -> void:
	_active = theme


static func deactivate() -> void:
	_active = null


static func is_active() -> bool:
	return _active != null


static func active() -> GuiTheme:
	return _active


## A stock colour in the active theme's dress, or itself when no GUI
## theme is in force. Painting code (PixelButtonStyle) calls this so its
## generated frames follow the theme without knowing it exists.
static func remap_color(stock_color: Color) -> Color:
	return _active.map_color(stock_color) if _active != null else stock_color


## One role of the active theme, or `fallback` when none is in force.
static func role_color(role: String, fallback: Color) -> Color:
	return _active.color(role) if _active != null else fallback


# =============================================================================
# BUILDING THE GODOT THEME
# =============================================================================

## The Theme resource the HUD root wears while this design is in force:
## the same coverage as assets/themes/game_theme.tres (buttons, labels,
## panels, scrollbars, tooltips) extended to the controls that file left
## to the engine default - fields, menus, tabs, sliders, progress bars -
## so one theme dresses every standard control the same way.
func build_theme() -> Theme:
	var theme := Theme.new()
	theme.default_font_size = metric("font_size")
	if font != null:
		theme.default_font = font

	var button_opacity := metricf("button_opacity")
	var normal := _flat(_with_opacity(color("button"), button_opacity), true, metric("button_radius"))
	var hover := _flat(_with_opacity(color("button_hover"), button_opacity), true, metric("button_radius"))
	hover.border_color = color("accent")
	var pressed := _flat(_with_opacity(color("button_pressed"), button_opacity), true, metric("button_radius"))
	var disabled := _flat(_with_opacity(color("button_disabled"), button_opacity), true, metric("button_radius"))
	var focus := _flat(Color(color("focus").r, color("focus").g, color("focus").b, 0.09),
		true, metric("button_radius") + 1)
	focus.border_color = color("focus")
	focus.set_border_width_all(metric("border_width") + 2)
	focus.set_expand_margin_all(3.0)
	focus.shadow_color = color("deep")
	focus.shadow_size = 2

	for type in ["Button", "OptionButton"]:
		theme.set_stylebox("normal", type, normal)
		theme.set_stylebox("hover", type, hover)
		theme.set_stylebox("pressed", type, pressed)
		theme.set_stylebox("disabled", type, disabled)
		theme.set_stylebox("focus", type, focus)
		theme.set_stylebox("hover_pressed", type, hover)
		theme.set_color("font_color", type, color("text"))
		theme.set_color("font_hover_color", type, color("text"))
		theme.set_color("font_pressed_color", type, color("text"))
		theme.set_color("font_focus_color", type, color("text"))
		theme.set_color("font_hover_pressed_color", type, color("text"))
		theme.set_color("font_disabled_color", type, color("text_muted"))
		theme.set_font_size("font_size", type, metric("font_size"))

	theme.set_color("font_color", "Label", color("text"))
	theme.set_font_size("font_size", "Label", metric("font_size"))
	theme.set_color("default_color", "RichTextLabel", color("text"))
	theme.set_font_size("normal_font_size", "RichTextLabel", metric("font_size"))

	var panel := _flat(_with_opacity(color("panel"), metricf("panel_opacity")), true, metric("panel_radius"))
	panel.content_margin_left = 12.0
	panel.content_margin_top = 12.0
	panel.content_margin_right = 12.0
	panel.content_margin_bottom = 12.0
	panel.shadow_color = Color(color("deep").r, color("deep").g, color("deep").b, 0.4)
	panel.shadow_size = metric("shadow_size")
	panel.shadow_offset = Vector2(0, 3)
	theme.set_stylebox("panel", "PanelContainer", panel)
	theme.set_stylebox("panel", "Panel", panel)

	var inset := _flat(color("inset"), true, maxi(metric("panel_radius") - 4, 0))
	theme.set_stylebox("normal", "LineEdit", inset)
	theme.set_stylebox("read_only", "LineEdit", inset)
	var field_focus := _flat(Color(0, 0, 0, 0), true, maxi(metric("panel_radius") - 4, 0))
	field_focus.border_color = color("focus")
	field_focus.draw_center = false
	theme.set_stylebox("focus", "LineEdit", field_focus)
	theme.set_color("font_color", "LineEdit", color("text"))
	theme.set_color("font_placeholder_color", "LineEdit", color("text_muted"))
	theme.set_color("font_selected_color", "LineEdit", color("accent_text"))
	theme.set_color("caret_color", "LineEdit", color("accent"))
	theme.set_color("selection_color", "LineEdit",
		Color(color("accent").r, color("accent").g, color("accent").b, 0.35))
	theme.set_font_size("font_size", "LineEdit", metric("font_size"))
	theme.set_stylebox("normal", "TextEdit", inset)
	theme.set_stylebox("read_only", "TextEdit", inset)
	theme.set_stylebox("focus", "TextEdit", field_focus)
	theme.set_color("font_color", "TextEdit", color("text"))
	theme.set_color("caret_color", "TextEdit", color("accent"))
	theme.set_color("selection_color", "TextEdit",
		Color(color("accent").r, color("accent").g, color("accent").b, 0.35))
	theme.set_font_size("font_size", "TextEdit", metric("font_size"))

	for type in ["CheckBox", "CheckButton"]:
		theme.set_color("font_color", type, color("text"))
		theme.set_color("font_hover_color", type, color("accent"))
		theme.set_color("font_pressed_color", type, color("text"))
		theme.set_color("font_focus_color", type, color("text"))
		theme.set_color("font_disabled_color", type, color("text_muted"))
		theme.set_font_size("font_size", type, metric("font_size"))

	theme.set_stylebox("background", "ProgressBar", inset)
	var fill := _flat(color("accent"), false, metric("button_radius"))
	theme.set_stylebox("fill", "ProgressBar", fill)
	theme.set_color("font_color", "ProgressBar", color("text"))
	theme.set_font_size("font_size", "ProgressBar", metric("font_size"))

	var track := _flat(color("inset"), false, 6)
	var grabber := _flat(color("scrollbar"), false, 6)
	var grabber_hover := _flat(color("scrollbar_hover"), false, 6)
	var grabber_pressed := _flat(color("accent"), false, 6)
	for type in ["HScrollBar", "VScrollBar"]:
		theme.set_stylebox("scroll", type, track)
		theme.set_stylebox("grabber", type, grabber)
		theme.set_stylebox("grabber_highlight", type, grabber_hover)
		theme.set_stylebox("grabber_pressed", type, grabber_pressed)

	var line := StyleBoxLine.new()
	line.color = color("border")
	line.thickness = maxi(metric("border_width"), 1)
	theme.set_stylebox("separator", "HSeparator", line)
	theme.set_stylebox("separator", "VSeparator", line)

	var tooltip := _flat(color("tooltip"), true, maxi(metric("panel_radius") - 6, 0))
	tooltip.content_margin_left = 8.0
	tooltip.content_margin_top = 4.0
	tooltip.content_margin_right = 8.0
	tooltip.content_margin_bottom = 4.0
	theme.set_stylebox("panel", "TooltipPanel", tooltip)
	var tooltip_font := color("text") if color("tooltip").get_luminance() > 0.45 \
		else Color(0.96, 0.94, 0.87)
	theme.set_color("font_color", "TooltipLabel", tooltip_font)
	theme.set_font_size("font_size", "TooltipLabel", maxi(metric("font_size") - 2, 10))

	for type in ["TabBar", "TabContainer"]:
		theme.set_stylebox("tab_selected", type, normal)
		theme.set_stylebox("tab_unselected", type, inset)
		theme.set_stylebox("tab_hovered", type, hover)
		theme.set_stylebox("tab_disabled", type, disabled)
		theme.set_stylebox("tab_focus", type, focus)
		theme.set_color("font_selected_color", type, color("text"))
		theme.set_color("font_unselected_color", type, color("text_dim"))
		theme.set_color("font_hovered_color", type, color("text"))
		theme.set_color("font_disabled_color", type, color("text_muted"))
		theme.set_color("font_focus_color", type, color("text"))
		theme.set_font_size("font_size", type, metric("font_size"))
	theme.set_stylebox("panel", "TabContainer", panel)

	theme.set_stylebox("panel", "Tree", inset)
	theme.set_stylebox("selected", "Tree", _flat(color("primary"), false, 4))
	theme.set_stylebox("selected_focus", "Tree", _flat(color("primary_hover"), false, 4))
	theme.set_color("font_color", "Tree", color("text"))
	theme.set_color("font_selected_color", "Tree", color("text"))
	theme.set_font_size("font_size", "Tree", metric("font_size"))
	theme.set_stylebox("panel", "ItemList", inset)
	theme.set_stylebox("selected", "ItemList", _flat(color("primary"), false, 4))
	theme.set_stylebox("selected_focus", "ItemList", _flat(color("primary_hover"), false, 4))
	theme.set_color("font_color", "ItemList", color("text"))
	theme.set_color("font_selected_color", "ItemList", color("text"))
	theme.set_font_size("font_size", "ItemList", metric("font_size"))

	theme.set_stylebox("panel", "PopupMenu", panel)
	theme.set_stylebox("hover", "PopupMenu", hover)
	theme.set_stylebox("separator", "PopupMenu", line)
	theme.set_color("font_color", "PopupMenu", color("text"))
	theme.set_color("font_hovered_color", "PopupMenu", color("text"))
	theme.set_color("font_disabled_color", "PopupMenu", color("text_muted"))
	theme.set_font_size("font_size", "PopupMenu", metric("font_size"))

	for type in ["HSlider", "VSlider"]:
		theme.set_stylebox("slider", type, track)
		theme.set_stylebox("grabber_area", type, _flat(color("primary"), false, 6))
		theme.set_stylebox("grabber_area_highlight", type, _flat(color("primary_hover"), false, 6))
	return theme


## A colour at a fraction of its painted solidity (the opacity metrics).
static func _with_opacity(base: Color, opacity: float) -> Color:
	return Color(base.r, base.g, base.b, base.a * clampf(opacity, 0.0, 1.0))


func _flat(bg: Color, use_border: bool, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	if use_border:
		style.set_border_width_all(metric("border_width"))
		style.border_color = color("border")
	style.set_corner_radius_all(radius)
	style.content_margin_left = 14.0
	style.content_margin_top = 7.0
	style.content_margin_right = 14.0
	style.content_margin_bottom = 7.0
	return style
