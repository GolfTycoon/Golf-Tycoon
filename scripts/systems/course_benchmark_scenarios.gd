extends RefCounted
class_name CourseBenchmarkScenarios
## CourseBenchmarkScenarios - the fixed course matrix the benchmark tour runs.
##
## GTB-2 sampled whatever happened to be on screen, so two runs were only
## comparable on the same save, from the same camera. The tour instead builds
## the same seeded courses on every machine and varies one thing at a time
## around a baseline, so a slow number names the subsystem that is slow:
##
##  * course type - every CourseTheme, plus the generated, Quick Start and
##    prebuilt layouts the player can start from;
##  * amount of holes - 3 / 6 / 9 / 18;
##  * terrain types - natural generation per theme, plus seeded patches of
##    the paintable tiles each course leans on (sand, water, trees,
##    boulders, streams...);
##  * buildings and improvements - clubhouse-only lots up to a full resort
##    with facilities, decorations and the walking-path network;
##  * visiting golfers - 0 to 32 on course, with a share of each field
##    drawn from the location's visiting-golfer pool;
##  * camera movement - still overview, pan, zoom sweep, a full tour of
##    the holes, and one view rotation;
##  * terrain editing - nothing, brush painting, elevation sculpting, or a
##    stress patch that cycles every paintable tile;
##  * game speed - Normal, Fast (3x) and Ultra (8x).
##
## Everything here is data: CourseBenchmarkTour builds a scenario on the live
## course, PerformanceBenchmark summarizes what it measured, and the tests
## hold the matrix to its coverage promises. A scenario dictionary carries:
##
##   id, name            stable id and the label the tour banner shows
##   theme               CourseTheme.Type value
##   layout              "generated", "quick_start" or "prebuilt:<package>"
##   holes               holes the layout is expected to open
##   seed                natural-terrain and patch seed (never 0: a fixed
##                       course is the point)
##   terrain_patches     TerrainTypes.Type values scattered in seeded blobs
##   patch_blobs/radius  how much of that ground the course carries
##   buildings           buildings.json ids beyond the always-ensured clubhouse
##   decorations         how many Improvements-tab ornaments to place
##   paths               lay the generated walking-path network
##   golfers             field size to spawn for the simulation phase
##   visiting_fraction   share of the field asked from the visiting pool
##   speed               GameManager.GameSpeed value for simulate/edit
##   camera              still / pan / zoom / tour / tour_rotate
##   edit                none / paint / elevation / both / stress
##   weather             "clear" or "rain" (rain only applies when the
##                       company enabled weather; the tour records which)

const SUITE_QUICK := "quick"
const SUITE_FULL := "full"
const SUITE_IDS: Array[String] = [SUITE_QUICK, SUITE_FULL]

const CAMERA_PLANS: Array[String] = ["still", "pan", "zoom", "tour", "tour_rotate"]
const EDIT_PLANS: Array[String] = ["none", "paint", "elevation", "both", "stress"]
## Holes each shipped prebuilt package opens (PrebuiltCourseGenerator).
const PREBUILT_HOLES := {"starter": 3, "executive": 9, "standard9": 9, "championship18": 18}
const MAX_GOLFERS := 48
const MAX_DECORATIONS := 60

const T := TerrainTypes.Type
const THEME := CourseTheme.Type

# =============================================================================
# THE MATRIX
# =============================================================================

## Every scenario of the full tour, in running order: a baseline first, the
## themed courses and one-variable sweeps after it, and the worst case last so
## the tour builds to its heaviest scene.
static func full_suite() -> Array:
	return [
		_scenario("baseline_parkland_9", "Baseline — Parkland 9", THEME.PARKLAND,
			"generated", 9, 7101,
			[T.BUNKER, T.WATER, T.OAK, T.FLOWER_BED], 6, 2,
			["pro_shop", "snack_bar", "putting_green"], 6, true,
			8, 0.25, GameManager.GameSpeed.NORMAL, "tour", "both"),
		_scenario("desert_starter_3", "Small course — Desert 3", THEME.DESERT,
			"generated", 3, 7202,
			[T.WASTE_BUNKER, T.ROCKS, T.CACTUS, T.SMALL_BOULDERS], 8, 2,
			["pro_shop"], 2, false,
			4, 0.0, GameManager.GameSpeed.NORMAL, "pan", "paint"),
		_scenario("links_coast_9", "Coast & wind — Links 9", THEME.LINKS,
			"generated", 9, 7303,
			[T.POT_BUNKER, T.FESCUE, T.DEEP_ROUGH, T.STREAM], 7, 2,
			["pub", "pro_shop", "cart_garage"], 4, true,
			8, 0.5, GameManager.GameSpeed.FAST, "zoom", "elevation"),
		_scenario("mountain_elevation_6", "Elevation — Mountain 6", THEME.MOUNTAIN,
			"generated", 6, 7404,
			[T.PINE, T.ROCKS, T.LARGE_BOULDERS, T.STREAM], 7, 2,
			["pro_shop", "snack_bar"], 3, true,
			6, 0.0, GameManager.GameSpeed.NORMAL, "tour", "elevation"),
		_scenario("woodland_dense_9", "Dense trees — Woodland 9", THEME.WOODLAND,
			"quick_start", 9, 7505,
			[T.OAK, T.PINE, T.MAPLE, T.BIRCH, T.SHRUB, T.TREES], 12, 3,
			["pro_shop", "stable"], 5, true,
			12, 0.25, GameManager.GameSpeed.FAST, "pan", "paint"),
		_scenario("marshland_water_9", "Water everywhere — Marshland 9", THEME.MARSHLAND,
			"generated", 9, 7606,
			[T.WATER, T.STREAM, T.CATTAILS, T.HEATHER], 9, 2,
			["snack_bar", "pro_shop"], 4, true,
			8, 0.25, GameManager.GameSpeed.NORMAL, "tour", "paint", "rain"),
		_scenario("city_executive_ultra", "Ultra speed — City Executive 9", THEME.CITY,
			"prebuilt:executive", 9, 7707,
			[T.OUT_OF_BOUNDS, T.BRUSH, T.FLOWER_BED], 4, 2,
			["pro_shop", "tennis_court"], 4, true,
			16, 0.0, GameManager.GameSpeed.ULTRA, "still", "none"),
		_scenario("resort_facilities_18", "Full facilities — Resort 18", THEME.RESORT,
			"generated", 18, 7808,
			[T.PALM, T.FLOWER_BED, T.WATER, T.FIRM_FAIRWAY], 8, 2,
			["pro_shop", "snack_bar", "putting_green", "driving_range", "spa",
				"swim_club", "resort_hotel", "tennis_court"], 24, true,
			16, 0.5, GameManager.GameSpeed.FAST, "tour", "both"),
		_scenario("heathland_edit_stress_9", "Editing stress — Heathland 9", THEME.HEATHLAND,
			"generated", 9, 7909,
			[T.HEATHER, T.DEEP_ROUGH, T.POT_BUNKER], 5, 2,
			["pro_shop"], 2, false,
			0, 0.0, GameManager.GameSpeed.NORMAL, "zoom", "stress"),
		_scenario("tropical_visitor_rush_18", "Visitor rush — Tropical 18", THEME.TROPICAL,
			"generated", 18, 8010,
			[T.PALM, T.WATER, T.ROCKS, T.BRUSH], 8, 2,
			["pro_shop", "snack_bar", "resort_hotel"], 10, true,
			24, 0.75, GameManager.GameSpeed.FAST, "tour", "paint"),
		_scenario("championship_stress_18", "Worst case — Championship 18", THEME.MOUNTAIN,
			"prebuilt:championship18", 18, 8111,
			[T.PINE, T.OAK, T.WATER, T.BUNKER, T.LARGE_BOULDERS, T.DEEP_ROUGH,
				T.STREAM, T.FLOWER_BED], 12, 3,
			["pro_shop", "snack_bar", "putting_green", "driving_range", "cart_garage",
				"spa", "swim_club", "resort_hotel", "castle"], 32, true,
			32, 0.5, GameManager.GameSpeed.ULTRA, "tour_rotate", "both"),
	]

## The short tour Settings runs: the baseline, a dense Fast course, the Ultra
## speed check and the full-facilities 18 — every subsystem touched once.
const QUICK_SCENARIO_IDS: Array[String] = [
	"baseline_parkland_9", "woodland_dense_9", "city_executive_ultra",
	"resort_facilities_18",
]

static func quick_suite() -> Array:
	var picked: Array = []
	for scenario in full_suite():
		if str(scenario.get("id", "")) in QUICK_SCENARIO_IDS:
			picked.append(scenario)
	return picked

## A suite by its stable id, shaped for the tour banner and the report.
## Unknown ids fall back to the quick tour rather than an empty run.
static func suite_by_id(suite_id: String) -> Dictionary:
	match suite_id:
		SUITE_FULL:
			return {"id": SUITE_FULL, "name": "Full course tour",
				"scenarios": full_suite()}
		_:
			return {"id": SUITE_QUICK, "name": "Quick course tour",
				"scenarios": quick_suite()}

static func suite_name(suite_id: String) -> String:
	return str(suite_by_id(suite_id).get("name", "Quick course tour"))

static func _scenario(id: String, name: String, theme: int, layout: String,
		holes: int, seed_value: int, terrain_patches: Array, patch_blobs: int,
		patch_radius: int, buildings: Array, decorations: int, paths: bool,
		golfers: int, visiting_fraction: float, speed: int, camera: String,
		edit: String, weather: String = "clear") -> Dictionary:
	return {
		"id": id, "name": name, "theme": theme, "layout": layout,
		"holes": holes, "seed": seed_value,
		"terrain_patches": terrain_patches, "patch_blobs": patch_blobs,
		"patch_radius": patch_radius, "buildings": buildings,
		"decorations": decorations, "paths": paths, "golfers": golfers,
		"visiting_fraction": visiting_fraction, "speed": speed,
		"camera": camera, "edit": edit, "weather": weather,
	}

## A minimal valid scenario with overrides — the shape tests and tools that
## drive a one-off tour start from, so they name only what they vary.
static func scenario_with(overrides: Dictionary = {}) -> Dictionary:
	var scenario := _scenario("custom", "Custom course", THEME.PARKLAND,
		"generated", 3, 4242, [T.BUNKER], 2, 1, ["pro_shop"], 1, true,
		2, 0.0, GameManager.GameSpeed.NORMAL, "tour", "both")
	for key in overrides:
		scenario[key] = overrides[key]
	return scenario

# =============================================================================
# READING A SCENARIO
# =============================================================================

static func theme_name(scenario: Dictionary) -> String:
	return CourseTheme.get_theme_name(int(scenario.get("theme", THEME.PARKLAND)))

static func speed_name(speed: int) -> String:
	match speed:
		GameManager.GameSpeed.PAUSED: return "Paused"
		GameManager.GameSpeed.FAST: return "Fast 3×"
		GameManager.GameSpeed.ULTRA: return "Ultra 8×"
		_: return "Normal 1×"

static func layout_name(scenario: Dictionary) -> String:
	var layout := str(scenario.get("layout", "generated"))
	if layout.begins_with("prebuilt:"):
		var package_id := layout.trim_prefix("prebuilt:")
		return str(PrebuiltCourseGenerator.PACKAGE_NAMES.get(package_id,
			package_id.capitalize()))
	return "Quick Start" if layout == "quick_start" else "Generated"

## "Parkland · Generated · 9 holes · 8 golfers (2 visiting) · Fast 3×" —
## the one line the tour banner and the results table describe a run with.
static func describe(scenario: Dictionary) -> String:
	var golfers := int(scenario.get("golfers", 0))
	var visiting := int(round(float(golfers) \
		* float(scenario.get("visiting_fraction", 0.0))))
	var field := "no golfers" if golfers <= 0 else "%d golfers" % golfers
	if visiting > 0:
		field += " (%d visiting)" % visiting
	return "%s · %s · %d holes · %s · %s" % [
		theme_name(scenario), layout_name(scenario),
		int(scenario.get("holes", 0)), field,
		speed_name(int(scenario.get("speed", GameManager.GameSpeed.NORMAL))),
	]

## The terrain tile names a scenario stamps, for the report.
static func terrain_patch_names(scenario: Dictionary) -> Array[String]:
	var names: Array[String] = []
	for terrain in scenario.get("terrain_patches", []):
		names.append(TerrainTypes.get_type_name(int(terrain)))
	return names

# =============================================================================
# COVERAGE - what a suite actually exercises
# =============================================================================

## Every value of `key` a suite carries, in first-seen order.
static func covered(scenarios: Array, key: String) -> Array:
	var values: Array = []
	for scenario in scenarios:
		var value: Variant = (scenario as Dictionary).get(key)
		if value != null and not values.has(value):
			values.append(value)
	return values

## Every TerrainTypes.Type a suite asks its patches or its editing for.
static func covered_terrain_types(scenarios: Array) -> Array:
	var types: Array = []
	for scenario in scenarios:
		for terrain in (scenario as Dictionary).get("terrain_patches", []):
			if not types.has(int(terrain)):
				types.append(int(terrain))
		# An edit-stress scenario cycles every paintable tile by definition.
		if str((scenario as Dictionary).get("edit", "")) == "stress":
			for terrain in edit_cycle_types():
				if not types.has(terrain):
					types.append(terrain)
	return types

## Every buildings.json id a suite places (the clubhouse is always placed).
static func covered_buildings(scenarios: Array) -> Array:
	var ids: Array = ["clubhouse"]
	for scenario in scenarios:
		for building_id in (scenario as Dictionary).get("buildings", []):
			if not ids.has(str(building_id)):
				ids.append(str(building_id))
	return ids

## The tiles the editing phase paints, in order: every paintable course tile
## except the two that open holes (a stray tee or cup would change the
## course being measured), then the landscape tiles.
static func edit_cycle_types() -> Array[int]:
	var types: Array[int] = []
	for terrain in TerrainTypes.COURSE_PAINT_TYPES:
		if terrain in [T.TEE_BOX, T.GREEN]:
			continue
		types.append(terrain)
	for terrain in TerrainTypes.COURSE_LANDSCAPE_TERRAIN_TYPES:
		types.append(terrain)
	return types

# =============================================================================
# VALIDATION - the matrix is held to its own promises
# =============================================================================

## Problems with a suite, in player-free language: empty when every scenario
## can be built as written. `building_ids` is the catalogue to check the
## building lists against (empty skips that check).
static func validate_suite(scenarios: Array, building_ids: Array = []) -> Array[String]:
	var problems: Array[String] = []
	if scenarios.is_empty():
		problems.append("the suite has no scenarios")
	var seen_ids: Dictionary = {}
	var seen_seeds: Dictionary = {}
	for scenario in scenarios:
		var entry: Dictionary = scenario
		var id := str(entry.get("id", ""))
		if id.is_empty():
			problems.append("a scenario has no id")
			continue
		if seen_ids.has(id):
			problems.append("%s: duplicate scenario id" % id)
		seen_ids[id] = true
		var seed_value := int(entry.get("seed", 0))
		if seed_value == 0:
			problems.append("%s: seed 0 would draw a different course each run" % id)
		if seen_seeds.has(seed_value):
			problems.append("%s: seed shared with another scenario" % id)
		seen_seeds[seed_value] = true
		problems.append_array(_validate_scenario(entry, building_ids))
	return problems

static func _validate_scenario(scenario: Dictionary, building_ids: Array) -> Array[String]:
	var problems: Array[String] = []
	var id := str(scenario.get("id", "?"))
	var theme := int(scenario.get("theme", -1))
	if theme < 0 or theme > THEME.MARSHLAND:
		problems.append("%s: theme %d is not a course type" % [id, theme])
	var layout := str(scenario.get("layout", ""))
	var holes := int(scenario.get("holes", 0))
	if layout == "generated":
		if holes not in GeneratedCourse.SUPPORTED_HOLE_COUNTS or holes <= 0:
			problems.append("%s: generated layouts open %s holes, not %d"
				% [id, str(GeneratedCourse.SUPPORTED_HOLE_COUNTS), holes])
	elif layout == "quick_start":
		if holes != 9:
			problems.append("%s: the Quick Start layout opens 9 holes, not %d" % [id, holes])
	elif layout.begins_with("prebuilt:"):
		var package_id := layout.trim_prefix("prebuilt:")
		if not PREBUILT_HOLES.has(package_id):
			problems.append("%s: unknown prebuilt package %s" % [id, package_id])
		elif int(PREBUILT_HOLES[package_id]) != holes:
			problems.append("%s: %s opens %d holes, not %d"
				% [id, package_id, int(PREBUILT_HOLES[package_id]), holes])
	else:
		problems.append("%s: unknown layout %s" % [id, layout])
	for terrain in scenario.get("terrain_patches", []):
		var type := int(terrain)
		if type in [T.TEE_BOX, T.GREEN, T.EMPTY, T.RETIRED_PATH]:
			problems.append("%s: patches must not stamp %s"
				% [id, TerrainTypes.get_type_name(type)])
		elif type not in TerrainTypes.COURSE_PAINT_TYPES \
				and type not in TerrainTypes.COURSE_LANDSCAPE_TERRAIN_TYPES:
			problems.append("%s: terrain %d is not a paintable course tile" % [id, type])
	for building_id in scenario.get("buildings", []):
		if str(building_id) == "clubhouse":
			problems.append("%s: the clubhouse is always ensured, never listed" % id)
		elif not building_ids.is_empty() and str(building_id) not in building_ids:
			problems.append("%s: unknown building %s" % [id, str(building_id)])
	var golfers := int(scenario.get("golfers", 0))
	if golfers < 0 or golfers > MAX_GOLFERS:
		problems.append("%s: %d golfers is outside 0-%d" % [id, golfers, MAX_GOLFERS])
	var visiting := float(scenario.get("visiting_fraction", 0.0))
	if visiting < 0.0 or visiting > 1.0:
		problems.append("%s: visiting fraction %.2f is outside 0-1" % [id, visiting])
	var decorations := int(scenario.get("decorations", 0))
	if decorations < 0 or decorations > MAX_DECORATIONS:
		problems.append("%s: %d decorations is outside 0-%d" % [id, decorations, MAX_DECORATIONS])
	if int(scenario.get("speed", GameManager.GameSpeed.NORMAL)) not in [
			GameManager.GameSpeed.NORMAL, GameManager.GameSpeed.FAST,
			GameManager.GameSpeed.ULTRA]:
		problems.append("%s: game speed must be Normal, Fast or Ultra" % id)
	if str(scenario.get("camera", "")) not in CAMERA_PLANS:
		problems.append("%s: unknown camera plan %s" % [id, str(scenario.get("camera", ""))])
	if str(scenario.get("edit", "")) not in EDIT_PLANS:
		problems.append("%s: unknown edit plan %s" % [id, str(scenario.get("edit", ""))])
	return problems
