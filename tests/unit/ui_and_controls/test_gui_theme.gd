extends GameTest
## GuiTheme and GuiThemeApplier: the palette format a GUI theme mod ships
## (roles, metrics, derivations, warnings), the Theme built from it, the
## stock-colour re-mapping, and the tree walk that dresses code-built HUD
## and panel overrides - at build time and as late controls appear.
## (scripts/ui/gui_theme.gd, scripts/ui/gui_theme_applier.gd)

const GLASS: Dictionary = {
	"name": "Test Glass",
	"colors": {
		"panel": "112233f0", "button": "445566", "text": "fefefe",
		"accent": "11ffee", "border": "a0b0c0",
	},
	"metrics": {"panel_radius": 22, "button_radius": 3},
}


func after_each() -> void:
	GuiTheme.deactivate()
	restore_live_content()
	super()


func _theme(spec: Dictionary = GLASS) -> GuiTheme:
	return GuiTheme.from_dictionary(spec)


# ---------------------------------------------------------------------------
# The stock palette and the Theme built from a design
# ---------------------------------------------------------------------------

func test_the_stock_theme_matches_the_shipped_game_theme() -> void:
	var shipped := load("res://assets/themes/game_theme.tres") as Theme
	var stock := GuiTheme.stock()
	assert_true(GuiTheme._same_color(stock.color("panel"),
		(shipped.get_stylebox("panel", "PanelContainer") as StyleBoxFlat).bg_color),
		"the default panel is the .tres panel, so an unthemed readback is the stock game")
	assert_true(GuiTheme._same_color(stock.color("button"),
		(shipped.get_stylebox("normal", "Button") as StyleBoxFlat).bg_color))
	assert_true(GuiTheme._same_color(stock.color("text"), shipped.get_color("font_color", "Label")))
	assert_eq(shipped.get_font_size("font_size", "Button"), stock.metric("font_size"))


func test_a_partial_theme_inherits_what_it_leaves_out() -> void:
	var theme := _theme({"colors": {"accent": "ff0000"}})
	assert_eq(theme.color("accent"), Color("ff0000"))
	assert_true(GuiTheme._same_color(theme.color("panel"), GuiTheme.default_colors()["panel"]),
		"an unmentioned panel keeps the stock fill")
	assert_eq(theme.warnings, [], "a small palette is complete, not broken")


func test_an_explicit_button_derives_its_missing_states() -> void:
	var theme := _theme({"colors": {"button": "204060"}})
	var base := Color("204060")
	assert_gt(theme.color("button_hover").get_luminance(), base.get_luminance(),
		"hover lifts from the themed button")
	assert_lt(theme.color("button_pressed").get_luminance(), base.get_luminance(),
		"pressed sinks from it")
	assert_lt(theme.color("button_disabled").a, base.a, "disabled fades from it")
	var explicit := _theme({"colors": {"button": "204060", "button_hover": "a0b0c0"}})
	assert_eq(explicit.color("button_hover"), Color("a0b0c0"),
		"an explicit state is never derived over")


func test_broken_entries_warn_once_and_keep_the_stock_value() -> void:
	var theme := _theme({"colors": {"accent": "not-a-colour", "mystery": "ffffff"},
		"metrics": {"panel_radius": 99, "font_size": "big"}})
	assert_eq(theme.warnings.size(), 3, "%s" % str(theme.warnings))
	assert_true(GuiTheme._same_color(theme.color("accent"), GuiTheme.default_colors()["accent"]))
	assert_eq(theme.metric("panel_radius"), 32, "an out-of-range metric is clamped, not fatal")


func test_the_built_theme_dresses_every_standard_control_family() -> void:
	var built := _theme().build_theme()
	var button := (built.get_stylebox("normal", "Button") as StyleBoxFlat)
	assert_true(GuiTheme._same_color(button.bg_color, Color("445566")),
		"buttons wear the theme's button colour")
	assert_eq(button.corner_radius_top_left, 3, "and the theme's button radius")
	assert_true(GuiTheme._same_color(built.get_color("font_color", "Label"), Color("fefefe")),
		"labels wear the theme's text colour")
	assert_true(GuiTheme._same_color(
		(built.get_stylebox("normal", "LineEdit") as StyleBoxFlat).bg_color,
		_theme().color("inset")), "fields sit in the inset colour")
	assert_true(GuiTheme._same_color(
		(built.get_stylebox("fill", "ProgressBar") as StyleBoxFlat).bg_color,
		Color("11ffee")), "progress fills spend the accent")
	assert_eq(built.default_font_size, 14)


# ---------------------------------------------------------------------------
# Re-mapping stock colours
# ---------------------------------------------------------------------------

func test_map_color_moves_stock_colours_and_leaves_foreign_ones() -> void:
	var theme := _theme()
	var mapped_panel := theme.map_color(Color("182f29f5"))
	assert_almost_eq(mapped_panel.r, theme.color("panel").r, 0.01,
		"a stock panel fill becomes the theme's panel")
	assert_almost_eq(mapped_panel.g, theme.color("panel").g, 0.01)
	assert_almost_eq(mapped_panel.b, theme.color("panel").b, 0.01)
	assert_lt(mapped_panel.a, theme.color("panel").a,
		"scaled by the stock fill's own translucency against the role's")
	var foreign := Color(0.13, 0.57, 0.91, 0.42)
	assert_true(GuiTheme._same_color(theme.map_color(foreign), foreign),
		"a colour the stock palette never uses (a shirt, a score) stays its own")
	var rail := theme.map_color(Color(0.031, 0.071, 0.059, 0.72))
	assert_lt(rail.a, theme.color("panel").a,
		"translucent stock surfaces stay proportionally translucent")
	assert_eq(theme.role_for(Color("e5c57c")), "accent", "the stock gold is the accent role")


func test_pixel_frames_are_painted_from_the_active_theme() -> void:
	var accent := Color("e5c57c")
	var fill := MenuStyle.CARD_BG
	GuiTheme.deactivate()
	var stock_image := (PixelButtonStyle.texture_style(accent,
		PixelButtonStyle.State.NORMAL, fill).texture as ImageTexture).get_image()
	GuiTheme.activate(_theme())
	var themed_image := (PixelButtonStyle.texture_style(accent,
		PixelButtonStyle.State.NORMAL, fill).texture as ImageTexture).get_image()
	assert_ne(themed_image.get_data(), stock_image.get_data(),
		"menu cards are generated from the themed palette while a theme is in force")
	GuiTheme.deactivate()
	var again := (PixelButtonStyle.texture_style(accent,
		PixelButtonStyle.State.NORMAL, fill).texture as ImageTexture).get_image()
	assert_eq(again.get_data(), stock_image.get_data(), "and from the stock palette without one")


func test_register_gui_theme_through_the_mod_api() -> void:
	var mod_api := ModAPI.new("tester.gui", ModManager, "res://")
	mod_api.register_gui_theme({"name": "API Glass", "colors": {"accent": "123456"}})
	assert_eq(ModManager.gui_theme_owner(), "tester.gui")
	assert_eq(ModManager.get_gui_theme().theme_name, "API Glass")
	assert_eq(ContentRegistry.get_gui_theme_source(), "tester.gui")


# ---------------------------------------------------------------------------
# The applier over a live control tree
# ---------------------------------------------------------------------------

func _stock_flat(bg: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = bg
	style.set_border_width_all(1)
	style.border_color = Color("63715a")
	style.set_corner_radius_all(16)
	style.shadow_color = Color(0.008, 0.043, 0.031, 0.4)
	style.shadow_size = 6
	return style


func _dressed_tree() -> Dictionary:
	var root := PanelContainer.new()
	root.add_theme_stylebox_override("panel", _stock_flat(GuiTheme.default_colors()["panel"]))
	var button := Button.new()
	button.text = "Swing"
	button.add_theme_stylebox_override("normal", _stock_flat(GuiTheme.default_colors()["button"]))
	root.add_child(button)
	var label := Label.new()
	label.text = "Money"
	label.add_theme_color_override("font_color", Color("f4edd9"))
	label.add_theme_font_size_override("font_size", 14)
	root.add_child(label)
	var foreign := PanelContainer.new()
	foreign.add_theme_stylebox_override("panel", _stock_flat(Color(0.13, 0.57, 0.91)))
	root.add_child(foreign)
	return {"root": root, "button": button, "label": label, "foreign": foreign}


func test_the_applier_restyles_overrides_and_reshapes_boxes() -> void:
	var tree := _dressed_tree()
	var root := tree["root"] as PanelContainer
	add_child_autofree(root)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(root, _theme())
	var panel := root.get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(GuiTheme._same_color(panel.bg_color, _theme().color("panel")),
		"a code-built panel fill takes the theme's panel colour")
	assert_true(GuiTheme._same_color(panel.border_color, Color("a0b0c0")),
		"its stock border takes the theme's")
	assert_eq(panel.corner_radius_top_left, 22,
		"panel shapes follow the theme, not only its hues")
	var button := (tree["button"] as Button).get_theme_stylebox("normal") as StyleBoxFlat
	assert_true(GuiTheme._same_color(button.bg_color, Color("445566")))
	assert_eq(button.corner_radius_top_left, 3, "buttons take the button radius")
	assert_true(GuiTheme._same_color((tree["label"] as Label).get_theme_color("font_color"),
		Color("fefefe")), "label colours are re-mapped too")
	var foreign := (tree["foreign"] as PanelContainer).get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(GuiTheme._same_color(foreign.bg_color, Color(0.13, 0.57, 0.91)),
		"colours outside the stock palette are left exactly as built")


func test_the_applier_themes_the_font_size_it_knows() -> void:
	var sized := GuiTheme.from_dictionary({"metrics": {"font_size": 17}})
	var label := Label.new()
	label.add_theme_font_size_override("font_size", 14)
	add_child_autofree(label)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(label, sized)
	assert_eq(label.get_theme_font_size("font_size"), 17,
		"the stock base size follows the theme")
	var title := Label.new()
	add_child_autofree(title)
	title.add_theme_font_size_override("font_size", 24)
	applier.style_control(title)
	assert_eq(title.get_theme_font_size("font_size"), 24, "display sizes are left alone")


func test_the_applier_dresses_controls_that_arrive_late() -> void:
	var root := VBoxContainer.new()
	add_child_autofree(root)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(root, _theme())
	var late := Button.new()
	late.add_theme_stylebox_override("normal", _stock_flat(GuiTheme.default_colors()["button"]))
	root.add_child(late)
	await process_frames(3)
	var dressed := late.get_theme_stylebox("normal") as StyleBoxFlat
	assert_true(GuiTheme._same_color(dressed.bg_color, Color("445566")),
		"popups and panels built after startup are dressed as they appear")


# ---------------------------------------------------------------------------
# The bottom bar's own colours
# ---------------------------------------------------------------------------

func test_the_bottom_bar_family_derives_from_one_colour() -> void:
	var theme := _theme({"colors": {"bottom_bar": "1a2b3c"}})
	assert_eq(theme.color("bottom_bar"), Color("1a2b3c"))
	assert_gt(theme.color("bottom_bar_light").get_luminance(),
		theme.color("bottom_bar").get_luminance(), "the light turf lifts from the bar")
	assert_lt(theme.color("bottom_bar_socket").get_luminance(),
		theme.color("bottom_bar").get_luminance(), "the sockets sink below it")
	assert_eq(theme.role_for(Color("10241a")), "bottom_bar",
		"the fan's dark turf is the bottom_bar role")
	var explicit := _theme({"colors": {"bottom_bar": "1a2b3c", "bottom_bar_light": "aabbcc"}})
	assert_eq(explicit.color("bottom_bar_light"), Color("aabbcc"),
		"an explicit companion is never derived over")


func test_the_bottom_fans_are_painted_from_the_active_theme() -> void:
	var theme := _theme({"colors": {"bottom_bar": "334455"}})
	var canvas := Vector2(96, 64)
	var circles: Array = []
	GuiTheme.deactivate()
	var stock_fan := DockArcBackdrop.arc_image(canvas, circles, [],
		DockArcBackdrop.FALLBACK_ACCENT)
	GuiTheme.activate(theme)
	var glass_fan := DockArcBackdrop.arc_image(canvas, circles, [],
		DockArcBackdrop.FALLBACK_ACCENT)
	GuiTheme.deactivate()
	var again := DockArcBackdrop.arc_image(canvas, circles, [],
		DockArcBackdrop.FALLBACK_ACCENT)
	assert_eq(stock_fan.get_pixel(0, 0), DockArcBackdrop.TURF_DARK,
		"no theme, no change: the fan is its stock turf")
	assert_eq(glass_fan.get_pixel(0, 0), theme.color("bottom_bar"),
		"the dock fan is painted from the theme's bottom_bar")
	assert_eq(again.get_data(), stock_fan.get_data(),
		"and the cached stock fan comes back when the theme leaves")
	var hub := Vector2(0, canvas.y)
	var stock_shelf := ShelfFanBackdrop.shelf_image(canvas, hub, [],
		ShelfFanBackdrop.FALLBACK_ACCENT)
	GuiTheme.activate(theme)
	var glass_shelf := ShelfFanBackdrop.shelf_image(canvas, hub, [],
		ShelfFanBackdrop.FALLBACK_ACCENT)
	GuiTheme.deactivate()
	assert_ne(glass_shelf.get_data(), stock_shelf.get_data(),
		"the shelf fan follows the same palette")
	var shelf_turf := false
	for y in glass_shelf.get_height():
		for x in glass_shelf.get_width():
			if glass_shelf.get_pixel(x, y) == theme.color("bottom_bar"):
				shelf_turf = true
	assert_true(shelf_turf, "its turf wears the theme's bottom_bar")


# ---------------------------------------------------------------------------
# Opacity and fonts
# ---------------------------------------------------------------------------

func test_opacity_metrics_fade_backgrounds_in_the_built_theme() -> void:
	var theme := _theme({"colors": {"button": "445566", "panel": "112233"},
		"metrics": {"button_opacity": 0.5, "panel_opacity": 0.25}})
	assert_almost_eq(theme.metricf("button_opacity"), 0.5, 0.001)
	var built := theme.build_theme()
	var button := built.get_stylebox("normal", "Button") as StyleBoxFlat
	assert_almost_eq(button.bg_color.a, 0.5, 0.01, "button backgrounds go translucent")
	assert_true(GuiTheme._same_color(Color(button.bg_color, 1.0), Color("445566")),
		"only the solidity changes, never the hue")
	var panel := built.get_stylebox("panel", "PanelContainer") as StyleBoxFlat
	assert_almost_eq(panel.bg_color.a, 0.25, 0.01, "panels fade by their own metric")
	var clamped := _theme({"metrics": {"button_opacity": 7, "panel_opacity": "half"}})
	assert_almost_eq(clamped.metricf("button_opacity"), 1.0, 0.001,
		"an opacity past solid clamps back to solid")
	assert_eq(clamped.warnings.size(), 1, "a non-number opacity warns once")


func test_the_applier_applies_the_opacity_metrics_to_code_built_boxes() -> void:
	var spec: Dictionary = GLASS.duplicate()
	spec["metrics"] = {"panel_radius": 22, "button_radius": 3, "panel_opacity": 0.5}
	var tree := _dressed_tree()
	var root := tree["root"] as PanelContainer
	add_child_autofree(root)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(root, _theme(spec))
	var panel := root.get_theme_stylebox("panel") as StyleBoxFlat
	assert_almost_eq(panel.bg_color.a, _theme(spec).color("panel").a * 0.5, 0.01,
		"code-built panels fade with the metric too")


func test_font_entries_keep_paths_and_accept_resources() -> void:
	var theme := _theme({"font": "fonts/Body.ttf", "font_bold": "fonts/Head.ttf"})
	assert_eq(theme.font_path, "fonts/Body.ttf")
	assert_eq(theme.font_bold_path, "fonts/Head.ttf")
	assert_null(theme.font, "a path is only a promise until the registry loads the file")
	var shipped := load("res://assets/fonts/PixelifySans-Black.ttf") as Font
	var resourced := _theme({"font": shipped})
	assert_eq(resourced.font, shipped, "code may hand over a Font directly")
	var broken := _theme({"font": 42})
	assert_eq(broken.warnings.size(), 1, "%s" % str(broken.warnings))
	assert_eq(broken.font_path, "", "and the stock font stands in")


func test_theme_fonts_dress_the_built_theme_and_stock_font_overrides() -> void:
	var black := load("res://assets/fonts/PixelifySans-Black.ttf") as Font
	var bold := load("res://assets/fonts/PixelifySans-Bold.ttf") as Font
	var regular := load("res://assets/fonts/PixelifySans-Regular.ttf") as Font
	var theme := _theme({})
	theme.font = black
	assert_eq(theme.build_theme().default_font, black,
		"the built Theme speaks the theme's font")
	var body := Label.new()
	body.add_theme_font_override("font", regular)
	add_child_autofree(body)
	var heading := Label.new()
	heading.add_theme_font_override("font", bold)
	add_child_autofree(heading)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(body, theme)
	applier.style_control(heading)
	assert_eq(body.get_theme_font("font"), black, "stock body faces become the theme font")
	assert_eq(heading.get_theme_font("font"), black,
		"display faces fall back to it when the palette names one font")
	theme.font = null
	theme.font_bold = bold
	var body_two := Label.new()
	body_two.add_theme_font_override("font", regular)
	add_child_autofree(body_two)
	var heading_two := Label.new()
	heading_two.add_theme_font_override("font", bold)
	add_child_autofree(heading_two)
	applier.setup(body_two, theme)
	applier.style_control(heading_two)
	assert_eq(body_two.get_theme_font("font"), regular,
		"a bold-only palette leaves body faces stock")
	assert_eq(heading_two.get_theme_font("font"), bold)


# ---------------------------------------------------------------------------
# Targeted rules
# ---------------------------------------------------------------------------

func test_rules_parse_and_warn_like_the_palette() -> void:
	var theme := _theme({"rules": [
		{"target": {"screen": "MainMenu", "type": "Button"}, "background": "365c43", "radius": 18},
		{"target": {"name": "ContinueButton"}, "text": "ffe9a8", "font_size": 20},
		{"target": {}, "background": "ffffff"},
		{"target": {"screen": "MainMenu"}, "bogus": 1},
		{"background": "ffffff"},
		{"target": {"type": "Button"}, "glyph": "no-such-glyph"},
	]})
	assert_eq(theme.rules.size(), 2, "only the sound rules survive: %s" % str(theme.rules))
	assert_eq(theme.warnings.size(), 6, "%s" % str(theme.warnings))
	assert_eq(theme.rules[0]["target"], {"screen": "MainMenu", "type": "Button"})
	assert_eq(theme.rules[0]["background"], Color("365c43"))


func test_rules_merge_by_specificity_then_order() -> void:
	var theme := _theme({"rules": [
		{"target": {"type": "Button"}, "background": "111111", "radius": 4},
		{"target": {"screen": "MainMenu", "type": "Button"}, "background": "222222"},
		{"target": {"name": "PlayButton"}, "text": "333333"},
		{"target": {"type": "Button"}, "background": "444444"},
	]})
	var style := theme.style_for("PlayButton", ["Button"],
		["PlayButton", "MainMenu", "Main"])
	assert_eq(style["background"], Color("222222"),
		"screen-and-type outweighs type alone, even a later one")
	assert_eq(style["radius"], 4, "properties merge across the rules that match")
	assert_eq(style["text"], Color("333333"), "a name rule adds its own say")
	var elsewhere := theme.style_for("PlayButton", ["Button"],
		["PlayButton", "ModsScreen", "Main"])
	assert_eq(elsewhere["background"], Color("444444"),
		"off that screen, the later type rule wins the tie")
	assert_true(theme.style_for("Title", ["Label"], ["Title", "MainMenu"]).is_empty(),
		"nothing matches, nothing styles")


func test_a_rule_dresses_one_named_button_only() -> void:
	var spec: Dictionary = GLASS.duplicate()
	spec["rules"] = [{"target": {"name": "ContinueButton"},
		"background": "7a1f1f", "radius": 2, "text": "ffe9a8", "font_size": 19}]
	var menu := Panel.new()
	menu.name = "MainMenu"
	var play := Button.new()
	play.name = "ContinueButton"
	play.text = "Continue"
	var other := Button.new()
	other.name = "ModsButton"
	other.text = "Mods"
	menu.add_child(play)
	menu.add_child(other)
	add_child_autofree(menu)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(menu, _theme(spec))
	var box := play.get_theme_stylebox("normal") as StyleBoxFlat
	assert_true(GuiTheme._same_color(box.bg_color, Color("7a1f1f")),
		"the named button wears the rule's background")
	assert_eq(box.corner_radius_top_left, 2, "and its radius")
	var hover := play.get_theme_stylebox("hover") as StyleBoxFlat
	assert_gt(hover.bg_color.get_luminance(), box.bg_color.get_luminance(),
		"its unlisted states derive from the rule's background")
	assert_true(GuiTheme._same_color(play.get_theme_color("font_color"), Color("ffe9a8")),
		"its text takes the rule's colour")
	assert_eq(play.get_theme_font_size("font_size"), 19, "and its font size")
	var sibling := other.get_theme_stylebox("normal") as StyleBoxFlat
	assert_true(GuiTheme._same_color(sibling.bg_color, Color("445566")),
		"its neighbour keeps the theme's ordinary button")


func test_a_rule_stays_on_its_own_screen() -> void:
	var spec: Dictionary = GLASS.duplicate()
	spec["rules"] = [{"target": {"screen": "ModsScreen", "type": "Button"},
		"background": "223344"}]
	var screens := VBoxContainer.new()
	screens.name = "Screens"
	var mods := Panel.new()
	mods.name = "ModsScreen"
	var mods_button := Button.new()
	mods_button.text = "Install"
	mods.add_child(mods_button)
	var menu := Panel.new()
	menu.name = "MainMenu"
	var menu_button := Button.new()
	menu_button.text = "Play"
	menu.add_child(menu_button)
	screens.add_child(mods)
	screens.add_child(menu)
	add_child_autofree(screens)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(screens, _theme(spec))
	var dressed := mods_button.get_theme_stylebox("normal") as StyleBoxFlat
	assert_true(GuiTheme._same_color(dressed.bg_color, Color("223344")),
		"every button on the named screen takes the rule")
	var untouched := menu_button.get_theme_stylebox("normal") as StyleBoxFlat
	assert_true(GuiTheme._same_color(untouched.bg_color, Color("445566")),
		"the same class of button one screen over does not")


func test_rules_set_button_icons_and_medallion_glyphs() -> void:
	var image := Image.create_empty(4, 4, false, Image.FORMAT_RGBA8)
	image.fill(Color.GREEN)
	var icon := ImageTexture.create_from_image(image)
	var spec: Dictionary = GLASS.duplicate()
	spec["rules"] = [
		{"target": {"name": "IconButton"}, "icon": icon},
		{"target": {"name": "MenuBtn"}, "glyph": "flag", "background": "334455"},
	]
	var root := Panel.new()
	var button := Button.new()
	button.name = "IconButton"
	button.text = "Go"
	root.add_child(button)
	var medallion := PixelCircleButton.new()
	medallion.name = "MenuBtn"
	root.add_child(medallion)
	add_child_autofree(root)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(root, _theme(spec))
	assert_eq(button.icon, icon, "a rule hands a plain button its picture")
	assert_eq(medallion.glyph, "flag", "a medallion swaps its pictogram")
	assert_eq(medallion.accent, Color("334455"),
		"and a medallion's background is its face colour")


func test_a_rule_can_fade_a_panel_without_repainting_it() -> void:
	var spec: Dictionary = GLASS.duplicate()
	spec["rules"] = [{"target": {"type": "PanelContainer"}, "opacity": 0.4}]
	var tree := _dressed_tree()
	var root := tree["root"] as PanelContainer
	add_child_autofree(root)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(root, _theme(spec))
	var panel := root.get_theme_stylebox("panel") as StyleBoxFlat
	assert_true(GuiTheme._same_color(Color(panel.bg_color, 1.0), Color("112233")),
		"the fill is the theme's panel, unrepainted")
	assert_almost_eq(panel.bg_color.a, _theme(spec).color("panel").a * 0.4, 0.01,
		"worn at the rule's solidity")


func test_rules_recolor_text_on_painted_frames_without_touching_their_art() -> void:
	var spec: Dictionary = GLASS.duplicate()
	spec["rules"] = [{"target": {"name": "CardButton"},
		"background": "ff0000", "text": "00ffcc"}]
	var root := Panel.new()
	var card := Button.new()
	card.name = "CardButton"
	card.text = "Tournament"
	var frame := StyleBoxTexture.new()
	frame.texture = ImageTexture.create_from_image(
		Image.create_empty(4, 4, false, Image.FORMAT_RGBA8))
	card.add_theme_stylebox_override("normal", frame)
	root.add_child(card)
	add_child_autofree(root)
	var applier := GuiThemeApplier.new()
	add_child_autofree(applier)
	applier.setup(root, _theme(spec))
	assert_same(card.get_theme_stylebox("normal"), frame,
		"a painted frame is the painter's business, never the rule's")
	assert_true(GuiTheme._same_color(card.get_theme_color("font_color"), Color("00ffcc")),
		"but its lettering still takes the rule's colour")
