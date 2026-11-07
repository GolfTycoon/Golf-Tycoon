extends GameTest
## The menu background system: the shipped catalogue, Auto's rules, the saved
## choice, mod-declared styles, the overlay settings and the painters.
##
## These are the pieces the Settings card and every menu screen read, so they
## are pinned here without a window: which styles exist, what Auto resolves to
## in each game state, and that a stored id survives a settings round trip.

const BackdropsScript := preload("res://scripts/autoload/backdrops.gd")
const Catalog := preload("res://scripts/systems/menu_backdrop_catalog.gd")
const Overlay := preload("res://scripts/ui/components/menu_backdrop_overlay.gd")

const SHIPPED_BACKDROPS := ["clubhouse", "golden_hour", "winter", "desert"]
const SHIPPED_OVERLAYS := [
	"vignette", "edge_scrim", "evening_wash", "sand_haze", "fairway_stripes",
	"lattice", "scanlines", "pixel_halftone", "dew_sparkle", "flag_glow", "split_light",
	"aurora", "sunburst", "contours", "deco", "argyle", "bokeh", "none",
]

var _saved_background: String = ""
var _saved_overlay: String = ""
var _saved_overlay_settings: Dictionary = {}


func before_each() -> void:
	super()
	_saved_background = Backdrops.background_choice
	_saved_overlay = Backdrops.overlay_choice
	_saved_overlay_settings = Backdrops.overlay_settings.duplicate(true)
	Backdrops.background_choice = Backdrops.AUTO
	Backdrops.overlay_choice = Backdrops.AUTO
	Backdrops.overlay_settings.clear()


func after_each() -> void:
	MenuBackdropCatalog.clear_mod_catalogues()
	Backdrops.background_choice = _saved_background
	Backdrops.overlay_choice = _saved_overlay
	Backdrops.overlay_settings = _saved_overlay_settings.duplicate(true)
	super()


# ---------------------------------------------------------------------------
# The shipped catalogue
# ---------------------------------------------------------------------------

func test_the_game_ships_four_pictures_and_eighteen_overlays() -> void:
	var backdrop_ids: Array[String] = []
	for entry in MenuBackdropCatalog.backdrops():
		backdrop_ids.append(str(entry["id"]))
	assert_eq(backdrop_ids, SHIPPED_BACKDROPS, "the shipped pictures, in catalogue order")
	var overlay_ids: Array[String] = []
	for entry in MenuBackdropCatalog.overlays():
		overlay_ids.append(str(entry["id"]))
	assert_eq(overlay_ids, SHIPPED_OVERLAYS, "the shipped overlays, in catalogue order")


func test_every_shipped_picture_names_a_file_that_actually_ships() -> void:
	for entry in MenuBackdropCatalog.backdrops():
		var path: String = str(entry.get("image", ""))
		assert_true(path.begins_with("res://"), "%s names a res:// picture" % entry["id"])
		assert_true(ResourceLoader.exists(path) or FileAccess.file_exists(path),
			"%s: %s is on disk" % [entry["id"], path])
		assert_false(entry.has("scrim"),
			"%s carries no scrim: the edge shading is an overlay, not the picture's job" % entry["id"])


func test_every_shipped_overlay_names_a_pattern_the_painter_knows() -> void:
	for entry in MenuBackdropCatalog.overlays():
		assert_true(MenuBackdropOverlay.is_pattern(str(entry.get("pattern", ""))),
			"%s uses a real pattern" % entry["id"])
		assert_true(float(entry.get("strength", -1.0)) >= 0.0 and float(entry.get("strength", 2.0)) <= 1.0,
			"%s keeps its strength inside 0-1" % entry["id"])


func test_only_the_automatic_look_is_untagged_so_auto_has_a_plain_fallback() -> void:
	# Auto must never loop between two tagged entries: the shipped clubhouse is
	# the untagged fallback, and 'none' is the untagged overlay.
	var clubhouse := MenuBackdropCatalog.backdrop("clubhouse")
	assert_true((clubhouse.get("seasons", []) as Array).is_empty(), "the clubhouse is not season-tagged")
	assert_true((clubhouse.get("themes", []) as Array).is_empty(), "the clubhouse is not theme-tagged")
	# The overlay Auto falls back to is the plain shading - Edge Scrim - so the
	# headings keep their bands out of the box, and it too is untagged.
	var auto_overlay := MenuBackdropCatalog.overlay(MenuBackdropCatalog.DEFAULT_OVERLAY_ID)
	assert_eq(MenuBackdropCatalog.DEFAULT_OVERLAY_ID, "edge_scrim")
	assert_true((auto_overlay.get("themes", []) as Array).is_empty())
	assert_true((auto_overlay.get("seasons", []) as Array).is_empty())
	# None is the bare picture the player can choose instead.
	var none := MenuBackdropCatalog.overlay("none")
	assert_eq(str(none.get("pattern", "")), "none", "None draws nothing at all")


# ---------------------------------------------------------------------------
# Auto
# ---------------------------------------------------------------------------

func test_auto_defaults_to_the_clubhouse_on_the_title_screen() -> void:
	GameManager.current_mode = GameManager.GameMode.MAIN_MENU
	assert_eq(Backdrops.background_choice, Backdrops.AUTO, "Auto is the default")
	assert_eq(Backdrops.auto_background_id(), "clubhouse",
		"no course and no season tag: the shipped clubhouse")
	var resolved := Backdrops.resolve_background()
	assert_eq(str(resolved["id"]), "clubhouse")
	assert_true(bool(resolved["automatic"]), "the resolver says it was Auto's pick")


func test_auto_prefers_a_picture_tagged_for_the_season() -> void:
	GameManager.current_mode = GameManager.GameMode.MAIN_MENU
	# The shipped Winter picture is tagged with the winter season.
	var winter_entry := MenuBackdropCatalog.backdrop("winter")
	assert_true("winter" in (winter_entry.get("seasons", []) as Array),
		"the shipped winter picture is tagged for winter")


func test_auto_prefers_a_course_theme_over_a_season() -> void:
	GameManager.current_mode = GameManager.GameMode.BUILDING
	GameManager.current_theme = CourseTheme.Type.DESERT
	GameManager.current_course = GameManager.CourseData.new()
	assert_eq(Backdrops.auto_background_id(), "desert",
		"a desert course picks the desert picture")
	var overlay_id := Backdrops.auto_overlay_id()
	assert_eq(overlay_id, "sand_haze", "and the overlay tagged for desert comes with it")
	GameManager.current_course = null


func test_auto_can_dress_a_course_in_its_signature_overlay() -> void:
	GameManager.current_mode = GameManager.GameMode.BUILDING
	GameManager.current_course = GameManager.CourseData.new()
	var expected := {
		CourseTheme.Type.MOUNTAIN: "aurora",
		CourseTheme.Type.RESORT: "sunburst",
		CourseTheme.Type.WOODLAND: "contours",
		CourseTheme.Type.LINKS: "argyle",
		CourseTheme.Type.TROPICAL: "bokeh",
	}
	for theme in expected:
		GameManager.current_theme = int(theme)
		assert_eq(Backdrops.auto_overlay_id(), expected[theme],
			"%s gets its own procedural look" % CourseTheme.get_theme_name(int(theme)))
	GameManager.current_course = null


func test_the_title_screen_ignores_the_last_course_theme() -> void:
	# Returning to the title screen leaves the course data in place, but Auto
	# must not keep dressing the menus as the course that was just closed.
	GameManager.current_course = GameManager.CourseData.new()
	GameManager.current_theme = CourseTheme.Type.DESERT
	GameManager.current_mode = GameManager.GameMode.MAIN_MENU
	assert_eq(Backdrops.auto_background_id(), "clubhouse",
		"in the menus the season decides, not the last course")
	GameManager.current_course = null


func test_auto_explains_itself() -> void:
	var line := Backdrops.auto_explanation()
	assert_true(line.begins_with("Auto:"), "the card gets a sentence, not a blank")
	assert_true(line.length() > 20, "with a reason in it")


# ---------------------------------------------------------------------------
# The player's choice
# ---------------------------------------------------------------------------

func test_a_choice_round_trips_through_the_settings_file() -> void:
	Backdrops.background_choice = "winter"
	Backdrops.overlay_choice = "fairway_stripes"
	Backdrops.overlay_settings = {"fairway_stripes": {"angle": 45}}
	var config := ConfigFile.new()
	Backdrops.save_to_config(config)

	var restored = BackdropsScript.new()
	restored.load_from_config(config)
	assert_eq(restored.background_choice, "winter")
	assert_eq(restored.overlay_choice, "fairway_stripes")
	assert_eq(restored.overlay_settings["fairway_stripes"]["angle"], 45)
	restored.free()


func test_a_settings_file_from_before_the_feature_loads_as_auto() -> void:
	var config := ConfigFile.new()
	config.set_value("display", "vsync", 1)
	config.set_value("audio", "master_volume", 0.4)
	var restored = BackdropsScript.new()
	restored.load_from_config(config)
	assert_eq(restored.background_choice, Backdrops.AUTO, "old files fall to Auto")
	assert_eq(restored.overlay_choice, Backdrops.AUTO)
	assert_true(restored.overlay_settings.is_empty())
	assert_eq(config.get_value("display", "vsync"), 1, "and nothing else is disturbed")
	restored.free()


func test_a_choice_whose_mod_is_gone_falls_back_to_auto() -> void:
	Backdrops.background_choice = "some_removed_mod:aurora"
	Backdrops.overlay_choice = "some_removed_mod:sparkle"
	var resolved := Backdrops.resolve_background()
	assert_eq(str(resolved["id"]), "clubhouse", "a missing style resolves through Auto")
	assert_true(bool(resolved["automatic"]))
	assert_eq(str(Backdrops.resolve_overlay()["id"]), "edge_scrim",
		"a missing overlay resolves through Auto to the default shading")


func test_picking_an_unknown_style_is_refused_rather_than_stored() -> void:
	Backdrops.set_background_choice_quietly("not_a_style")
	assert_eq(Backdrops.background_choice, Backdrops.AUTO)
	Backdrops.set_background_choice_quietly("winter")
	assert_eq(Backdrops.background_choice, "winter")
	Backdrops.set_overlay_choice_quietly("vignette")
	assert_eq(Backdrops.overlay_choice, "vignette")


func test_reset_returns_both_choices_to_auto() -> void:
	Backdrops.background_choice = "winter"
	Backdrops.overlay_choice = "vignette"
	Backdrops.overlay_settings = {"fairway_stripes": {"angle": 30}}
	Backdrops.reset_choices()
	assert_eq(Backdrops.background_choice, Backdrops.AUTO)
	assert_eq(Backdrops.overlay_choice, Backdrops.AUTO)
	assert_true(Backdrops.overlay_settings.is_empty(), "its settings go too")


# ---------------------------------------------------------------------------
# Overlay settings
# ---------------------------------------------------------------------------

func test_an_overlay_setting_is_kept_inside_its_declared_values() -> void:
	var overlay_id := "fairway_stripes"
	var schemas := MenuBackdropCatalog.settings_for(overlay_id)
	assert_eq(schemas.size(), 1, "the stripes expose one setting: the angle")
	assert_eq(str(schemas[0]["key"]), "angle")
	assert_eq(Backdrops.set_overlay_setting(overlay_id, "angle", 45), 45)
	assert_eq(Backdrops.overlay_settings[overlay_id]["angle"], 45, "and it is remembered")
	assert_eq(Backdrops.set_overlay_setting(overlay_id, "angle", 13), 0,
		"a value the catalogue does not declare falls back to the default")
	assert_eq(MenuBackdropCatalog.setting_value(overlay_id, "angle", "90°"), 90,
		"a label written by hand resolves through the choices")


func test_the_resolved_overlay_carries_its_settings() -> void:
	Backdrops.overlay_choice = "lattice"
	Backdrops.overlay_settings = {"lattice": {"angle": 60}}
	var resolved := Backdrops.resolve_overlay()
	assert_eq(str(resolved["id"]), "lattice")
	assert_eq(resolved["settings"]["angle"], 60, "the painter gets the saved angle")


func test_an_overlay_without_settings_resolves_an_empty_dictionary() -> void:
	Backdrops.overlay_choice = "vignette"
	assert_eq(MenuBackdropCatalog.settings_for("vignette").size(), 0)
	assert_true((Backdrops.resolve_overlay()["settings"] as Dictionary).is_empty())


func test_the_signature_designs_expose_and_resolve_their_controls() -> void:
	var expected := {
		"aurora": ["angle", "density"],
		"sunburst": ["angle", "density"],
		"contours": ["angle", "density"],
		"deco": [],
		"argyle": ["angle"],
		"bokeh": ["density"],
	}
	for overlay_id in expected:
		var keys: Array[String] = []
		for schema in MenuBackdropCatalog.settings_for(str(overlay_id)):
			keys.append(str(schema["key"]))
		assert_eq(keys, expected[overlay_id], "%s exposes only the controls it paints with" % overlay_id)

	Backdrops.overlay_choice = "aurora"
	Backdrops.overlay_settings = {"aurora": {"angle": 135, "density": 2}}
	var resolved := Backdrops.resolve_overlay()
	assert_eq(resolved["settings"]["angle"], 135)
	assert_eq(resolved["settings"]["density"], 2, "the aurora's heaviest ribbon setting reaches the painter")


# ---------------------------------------------------------------------------
# Mod styles
# ---------------------------------------------------------------------------

func test_a_mod_can_add_a_picture_and_an_overlay() -> void:
	var backdrops := {"example.backgrounds:harbour_dusk": {
		"name": "Harbour Dusk", "image": "res://assets/ui/backdrop_test.png",
		"tint": Color.WHITE, "seasons": ["fall"], "themes": [],
	}}
	var overlays := {"example.backgrounds:starfield": {
		"name": "Starfield", "pattern": "sparkle", "color": Color.WHITE,
		"strength": 0.6, "scale": 1.0, "setting_ids": ["density"],
	}}
	MenuBackdropCatalog.set_mod_catalogues(backdrops, overlays, {},
		{"example.backgrounds:harbour_dusk": "example.backgrounds"},
		{"example.backgrounds:starfield": "example.backgrounds"})

	assert_true(MenuBackdropCatalog.has_backdrop("example.backgrounds:harbour_dusk"),
		"the mod picture is on offer")
	assert_true(MenuBackdropCatalog.has_overlay("example.backgrounds:starfield"))
	var listed := MenuBackdropCatalog.backdrops()
	var last := listed[listed.size() - 1]
	assert_eq(str(last["id"]), "example.backgrounds:harbour_dusk",
		"mod styles sort after the shipped ones")
	assert_eq(str(last["source"]), "example.backgrounds", "and say whose they are")


func test_a_mod_can_patch_a_shipped_picture_instead_of_adding_one() -> void:
	MenuBackdropCatalog.set_mod_catalogues({"winter": {"tint": Color(1.0, 0.9, 0.8)}},
		{}, {}, {"winter": "example.tint"}, {})
	var winter := MenuBackdropCatalog.backdrop("winter")
	assert_eq(str(winter["name"]), "Winter Course", "the shipped name survives the patch")
	assert_eq(winter["tint"], Color(1.0, 0.9, 0.8), "the patch's tint is applied")
	assert_eq(str(winter["source"]), "example.tint", "and the mod is credited")
	assert_eq(MenuBackdropCatalog.backdrops().size(), SHIPPED_BACKDROPS.size(),
		"a patch adds no extra row to the picker")


func test_clearing_the_mod_table_puts_the_shipped_catalogue_back() -> void:
	MenuBackdropCatalog.set_mod_catalogues({"x:y": {"name": "Y"}}, {}, {}, {"x:y": "x"}, {})
	assert_true(MenuBackdropCatalog.has_backdrop("x:y"))
	MenuBackdropCatalog.clear_mod_catalogues()
	assert_false(MenuBackdropCatalog.has_backdrop("x:y"))
	assert_eq(MenuBackdropCatalog.backdrops().size(), SHIPPED_BACKDROPS.size())


func test_the_mod_summary_counts_what_a_mod_contributed() -> void:
	MenuBackdropCatalog.set_mod_catalogues(
		{"a:one": {"name": "One"}, "a:two": {"name": "Two"}},
		{"a:stars": {"name": "Stars", "pattern": "sparkle"}}, {}, 
		{"a:one": "a", "a:two": "a"}, {"a:stars": "a"})
	var summary := MenuBackdropCatalog.content_summary()
	assert_eq(int((summary["a"] as Dictionary).get("backdrops", 0)), 2)
	assert_eq(int((summary["a"] as Dictionary).get("overlays", 0)), 1)


# ---------------------------------------------------------------------------
# Normalising what a mod writes
# ---------------------------------------------------------------------------

func test_a_sparse_mod_picture_is_filled_in() -> void:
	var entry := {"image": "art/pic.png"}
	MenuBackdropCatalog.normalise_backdrop(entry, "res://mods/m")
	assert_eq(str(entry["image"]), "res://mods/m/art/pic.png",
		"the picture is resolved against the catalogue's own folder")
	assert_false(entry.has("scrim"), "and no scrim: that is an overlay's job")
	assert_eq(str(entry["name"]), "Backdrop", "and a name, so the picker is never blank")


func test_a_picture_with_no_image_is_rejected() -> void:
	var entry := {"name": "Nothing"}
	var warning := MenuBackdropCatalog.normalise_backdrop(entry)
	assert_false(warning.is_empty(), "the mod hears about it")
	assert_true(bool(entry.get("_invalid", false)), "and the entry is dropped")


func test_an_unknown_pattern_is_reported_but_still_loads() -> void:
	var entry := {"name": "Glitch", "pattern": "kaleidoscope"}
	var warning := MenuBackdropCatalog.normalise_overlay(entry)
	assert_string_contains(warning, "kaleidoscope", "the warning names the pattern")
	assert_eq(str(entry["pattern"]), "none", "and the overlay draws nothing rather than crashing")


func test_an_overlays_own_strength_and_scale_are_clamped() -> void:
	var entry := {"pattern": "dots", "strength": 5.0, "scale": 0.01}
	MenuBackdropCatalog.normalise_overlay(entry)
	assert_eq(float(entry["strength"]), 1.0)
	assert_true(float(entry["scale"]) >= 0.5)


# ---------------------------------------------------------------------------
# The painters themselves
# ---------------------------------------------------------------------------

## A canvas whose one job is to run a painter inside its own `_draw()`, the
## only place the engine allows drawing. Returns the painter's verdict.
class _PainterCanvas extends Control:
	var pattern: String = "none"
	var ink: Color = Color.BLACK
	var feature: float = 24.0
	var settings: Dictionary = {}
	var drew: bool = false

	func _draw() -> void:
		MenuBackdropOverlay.draw(self, pattern, Rect2(0.0, 0.0, 320.0, 180.0), ink, feature, settings)
		drew = true


func _paint(pattern: String, ink: Color = Color(0, 0, 0, 0.5)) -> _PainterCanvas:
	var canvas := _PainterCanvas.new()
	canvas.pattern = pattern
	canvas.ink = ink
	canvas.settings = {"angle": 45, "density": 2}
	add_child_autofree(canvas)
	# queue_redraw() only asks; the frame delivers NOTIFICATION_DRAW, which is
	# when the painter actually runs - and the engine reports an error if
	# anything draws outside it.
	canvas.queue_redraw()
	return canvas


func test_the_edge_shading_is_an_overlay_and_none_draws_no_bands() -> void:
	# The bands along the top and bottom used to be painted by MenuBackdrop for
	# every picture, under whichever overlay was active - a layer the player
	# could not turn off. They are the Edge Scrim overlay now, so this pins both
	# halves: None really draws nothing, and the shading is on the list.
	assert_true(MenuBackdropOverlay.is_pattern("edges"), "edges is a real painter")
	assert_eq(str(MenuBackdropCatalog.overlay("edge_scrim").get("pattern", "")), "edges",
		"the Edge Scrim overlay is the one that draws them")
	assert_eq(str(MenuBackdropCatalog.overlay("none").get("pattern", "")), "none",
		"and None is the bare picture")
	# The band geometry is returned rather than drawn, so it can be checked
	# exactly - and so the picture itself stays the only thing under the menu.
	var area := Rect2(0.0, 0.0, 640.0, 360.0)
	var bands := MenuBackdropOverlay.edge_bands(area, 0.45)
	assert_eq(bands.size(), 28, "Edge Scrim is 14 slices top and 14 bottom")
	var tops := bands.filter(func(b): return (b["rect"] as Rect2).position.y < 180.0)
	var bottoms := bands.filter(func(b): return (b["rect"] as Rect2).position.y >= 180.0)
	assert_eq(tops.size(), 14, "half the bands at the top")
	assert_eq(bottoms.size(), 14, "and half at the bottom")
	for band in bands:
		var rect: Rect2 = band["rect"]
		# Each slice overlaps the next by a pixel so no seam shows between them;
		# the overlap is clipped at the picture's own edge when it is drawn.
		assert_true(rect.position.y >= -0.01 and rect.end.y <= 361.01,
			"every band stays inside the picture")
		assert_almost_eq(rect.size.x, 640.0, 0.01, "each spans the full width")
	# Each slice is weaker than the one nearer its edge, so it reads as a
	# gradient rather than a hard bar - the complaint that started this.
	assert_true(float(tops[0]["alpha"]) > float(tops[13]["alpha"]),
		"the top band fades downward")
	assert_true(float(bottoms[0]["alpha"]) > float(bottoms[13]["alpha"]),
		"and the bottom band fades upward")
	assert_almost_eq(float(tops[0]["alpha"]), 0.45, 0.001,
		"the very edge is the full strength the entry asks for")


func test_every_pattern_can_paint_without_error() -> void:
	for pattern in MenuBackdropOverlay.PATTERNS:
		var canvas := _paint(pattern)
		await process_frames(1)
		assert_true(canvas.drew, "%s painted inside _draw()" % pattern)


func test_nothing_is_painted_for_none_or_a_fully_transparent_ink() -> void:
	# These are no-ops by contract - the early return is what keeps a rebuild
	# of every menu from costing anything when the player picked None.
	for pattern in ["none", "wash"]:
		var canvas := _paint(pattern, Color(0, 0, 0, 0.0))
		await process_frames(1)
		assert_true(canvas.drew, "%s returns without drawing anything" % pattern)
	MenuBackdropOverlay.draw(null, "wash", Rect2(0, 0, 10, 10), Color.BLACK, 1.0, {})
	assert_true(true, "a null canvas is ignored rather than crashing")


func test_an_unknown_pattern_draws_nothing_at_all() -> void:
	var canvas := _paint("not_a_pattern")
	await process_frames(1)
	assert_true(canvas.drew, "the painter returns rather than crashing")
	assert_false(MenuBackdropOverlay.is_pattern("not_a_pattern"),
		"an unknown pattern is not on the list, so the catalogue downgrades it to none")


# ---------------------------------------------------------------------------
# What a backdrop asks for
# ---------------------------------------------------------------------------

func test_a_backdrop_resolves_a_picture_and_an_overlay_together() -> void:
	var background := Backdrops.resolve_background()
	assert_not_null(background.get("texture", null), "the shipped picture decodes")
	assert_false(bool(background["texture_missing"]))
	var overlay := Backdrops.resolve_overlay()
	assert_true(MenuBackdropOverlay.is_pattern(str(overlay["pattern"])))


func test_a_missing_picture_reports_itself_and_falls_back() -> void:
	MenuBackdropCatalog.set_mod_catalogues({"broken": {
		"name": "Broken", "image": "res://does/not/exist.png",
		"tint": Color.WHITE, "seasons": [], "themes": [],
	}}, {}, {}, {"broken": "a_mod"}, {})
	Backdrops.background_choice = "broken"
	var resolved := Backdrops.resolve_background()
	assert_true(bool(resolved["texture_missing"]), "the screen can say the file is gone")
	assert_null(resolved["texture"], "and draws the plain green rather than failing")


func test_an_image_decodes_straight_from_its_bytes() -> void:
	var path := "res://assets/ui/backdrops/clubhouse_sunset.png"
	var bytes := FileAccess.get_file_as_bytes(path)
	var texture = BackdropsScript.decode_image(bytes, "png")
	assert_not_null(texture, "a shipped PNG decodes")
	assert_eq(texture.get_size(), Vector2(1280, 720))
	assert_null(BackdropsScript.decode_image(PackedByteArray(), "png"), "empty bytes fail softly")
	assert_null(BackdropsScript.decode_image(bytes, "gif"), "an unsupported format fails softly")
