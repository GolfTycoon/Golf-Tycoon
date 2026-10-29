extends GameTest
## PlayerDataStore - the catalogue behind the Settings screen's Data page.
##
## Every test points the store at a scratch folder (the static path overrides)
## so no test can touch the player's real saves, settings or skins. The store
## only applies live defaults while it points at the real files, which is why
## these tests are safe to run against a developer's own installation.

const ROOT := "user://test_player_data_store"
const SAVES := ROOT + "/saves/"
const SETTINGS := ROOT + "/settings.cfg"
const HISTORY := ROOT + "/benchmark_history.json"
const SNAPSHOT := ROOT + "/economic_snapshots.json"
const SKINS := ROOT + "/golfer_skins"

## Preference keys `_seed_settings` writes: 2 audio, 1 display, 1 controls,
## 1 camera, 1 gameplay and 1 graphics.
const PREFERENCE_KEYS := 7
const SAVED_FILES := 2
const ACHIEVEMENTS := 2
const BENCHMARK_RUNS := 2
const CUSTOM_SKINS := 2


func before_each() -> void:
	super()
	_remove_tree(ROOT)
	DirAccess.make_dir_recursive_absolute(SAVES)
	PlayerDataStore.saves_dir = SAVES
	PlayerDataStore.settings_path = SETTINGS
	PlayerDataStore.benchmark_history_path = HISTORY
	PlayerDataStore.economic_snapshot_path = SNAPSHOT
	PlayerDataStore.golfer_skins_dir = SKINS


func after_each() -> void:
	PlayerDataStore.restore_default_paths()
	_remove_tree(ROOT)
	super()


# ---------------------------------------------------------------------------
# Scratch data
# ---------------------------------------------------------------------------

func _write(path: String, text: String) -> void:
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()


func _remove_tree(path: String) -> void:
	if not DirAccess.dir_exists_absolute(path):
		return
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var full := path.path_join(entry)
			if dir.current_is_dir():
				_remove_tree(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)


func _seed_saves() -> void:
	for index in SAVED_FILES:
		_write(SAVES + "course_%d.save" % index, "{\"game_state\": {}}")


func _seed_settings() -> void:
	var config := ConfigFile.new()
	config.set_value("audio", "master_volume", 0.4)
	config.set_value("audio", "is_muted", false)
	config.set_value("display", "fps_counter_enabled", true)
	config.set_value("controls", "invert_zoom_scroll", true)
	config.set_value("camera", "min_zoom", 0.6)
	config.set_value("gameplay", "player_skin", "custom_skin")
	config.set_value("graphics", "grass_quality", 1)
	config.set_value("achievements", "unlocked", {"ach_first_steps": 4, "ach_ace": 9})
	config.set_value("achievements", "counters", {"holes_built": 3})
	config.set_value("tutorial", "completed", true)
	config.save(SETTINGS)


func _seed_benchmarks() -> void:
	_write(HISTORY, JSON.stringify({"version": 2, "runs": [
		{"at_unix": 1_700_000_000, "overall": 70.0},
		{"at_unix": 1_700_000_100, "overall": 74.0},
	]}))
	_write(SNAPSHOT, "[]")


func _seed_skins() -> void:
	for index in CUSTOM_SKINS:
		_write(SKINS.path_join("skin_%d" % index).path_join("skin.txt"), "id=skin_%d" % index)


func _seed_everything() -> void:
	_seed_saves()
	_seed_settings()
	_seed_benchmarks()
	_seed_skins()


func _settings() -> ConfigFile:
	var config := ConfigFile.new()
	config.load(SETTINGS)
	return config


# ---------------------------------------------------------------------------
# Reporting what is stored
# ---------------------------------------------------------------------------

func test_a_fresh_device_stores_nothing() -> void:
	for id in PlayerDataStore.GROUP_IDS:
		var use := PlayerDataStore.usage(id)
		assert_false(use["present"], "%s is empty" % id)
		assert_eq(use["count"], 0, "%s counts nothing" % id)
	assert_eq(PlayerDataStore.stored_group_count(), 0)
	assert_false(PlayerDataStore.anything_stored())
	assert_eq(PlayerDataStore.total_label(), "Nothing is stored on this device yet.")
	var result := PlayerDataStore.erase_all()
	assert_true(result["ok"], "erasing nothing is not an error")
	assert_eq(result["removed"], 0)


func test_every_group_reports_what_it_holds() -> void:
	_seed_everything()

	var saved := PlayerDataStore.usage(PlayerDataStore.SAVED_COURSES)
	assert_eq(saved["count"], SAVED_FILES)
	assert_true(saved["present"])
	assert_eq(saved["label"], "2 saved courses.")

	var preferences := PlayerDataStore.usage(PlayerDataStore.PREFERENCES)
	assert_eq(preferences["count"], PREFERENCE_KEYS, "every preference value counts once")
	assert_true(preferences["present"])

	var career := PlayerDataStore.usage(PlayerDataStore.CAREER)
	assert_eq(career["count"], ACHIEVEMENTS + 1, "two achievements and the tutorial flag")
	assert_string_contains(career["label"], "2 achievements")
	assert_string_contains(career["label"], "tutorial finished")

	var reports := PlayerDataStore.usage(PlayerDataStore.BENCHMARK_REPORTS)
	assert_eq(reports["count"], BENCHMARK_RUNS)
	assert_string_contains(reports["label"], "2 benchmark reports")

	var skins := PlayerDataStore.usage(PlayerDataStore.GOLFER_SKINS)
	assert_eq(skins["count"], CUSTOM_SKINS)
	assert_eq(skins["label"], "2 custom golfer skins.")

	assert_eq(PlayerDataStore.total_label(), "5 of 5 data groups hold something on this device.")


func test_the_store_watches_the_files_the_game_writes() -> void:
	# A path that drifts from the game's own constant would leave real player
	# data behind on a "delete everything".
	PlayerDataStore.restore_default_paths()
	assert_eq(PlayerDataStore.DEFAULT_SAVES_DIR, SaveManager.SAVE_DIR)
	assert_eq(PlayerDataStore.DEFAULT_SETTINGS_PATH, SaveManager.SETTINGS_PATH)
	assert_eq(PlayerDataStore.DEFAULT_BENCHMARK_HISTORY_PATH, BenchmarkHistory.DEFAULT_HISTORY_PATH)
	assert_eq(PlayerDataStore.DEFAULT_ECONOMIC_SNAPSHOT_PATH, GameManager.SNAPSHOT_PATH)
	assert_eq(PlayerDataStore.DEFAULT_GOLFER_SKINS_DIR, GolferSkinLibrary.USER_ROOT)


# ---------------------------------------------------------------------------
# Deleting one part
# ---------------------------------------------------------------------------

func test_deleting_saved_courses_leaves_everything_else_alone() -> void:
	_seed_everything()
	var result := PlayerDataStore.erase(PlayerDataStore.SAVED_COURSES)
	assert_true(result["ok"])
	assert_eq(result["removed"], SAVED_FILES)
	assert_false(PlayerDataStore.usage(PlayerDataStore.SAVED_COURSES)["present"])
	for index in SAVED_FILES:
		assert_false(FileAccess.file_exists(SAVES + "course_%d.save" % index))
	assert_true(FileAccess.file_exists(SETTINGS), "preferences and records stay")
	assert_true(FileAccess.file_exists(HISTORY), "the benchmark shelf stays")
	assert_true(DirAccess.dir_exists_absolute(SKINS), "the custom skins stay")


func test_resetting_preferences_keeps_career_records_and_saves() -> void:
	_seed_everything()
	var result := PlayerDataStore.erase(PlayerDataStore.PREFERENCES)
	assert_true(result["ok"])
	assert_eq(result["removed"], PREFERENCE_KEYS)
	var config := _settings()
	for section in PlayerDataStore.PREFERENCE_SECTIONS:
		assert_false(config.has_section(section), "%s is gone" % section)
	assert_true(config.has_section("achievements"), "the trophy case stays")
	assert_true(config.has_section("tutorial"), "the tutorial flag stays")
	assert_true(FileAccess.file_exists(SAVES + "course_0.save"), "saved courses stay")
	assert_true(PlayerDataStore.usage(PlayerDataStore.CAREER)["present"])


func test_deleting_career_records_keeps_preferences() -> void:
	_seed_everything()
	var result := PlayerDataStore.erase(PlayerDataStore.CAREER)
	assert_true(result["ok"])
	var config := _settings()
	assert_false(config.has_section("achievements"))
	assert_false(config.has_section("tutorial"))
	assert_true(config.has_section("audio"), "the mixer stays")
	assert_true(config.has_section("display"), "so do the display preferences")
	assert_true(FileAccess.file_exists(SAVES + "course_0.save"), "saved courses stay")


func test_deleting_benchmark_reports_removes_the_shelf_and_snapshot() -> void:
	_seed_everything()
	var result := PlayerDataStore.erase(PlayerDataStore.BENCHMARK_REPORTS)
	assert_true(result["ok"])
	assert_eq(result["removed"], BENCHMARK_RUNS + 1, "the two runs and the diagnostic snapshot")
	assert_false(FileAccess.file_exists(HISTORY))
	assert_false(FileAccess.file_exists(SNAPSHOT))
	assert_true(FileAccess.file_exists(SETTINGS), "nothing else is touched")


func test_deleting_custom_skins_removes_the_folder() -> void:
	_seed_everything()
	var result := PlayerDataStore.erase(PlayerDataStore.GOLFER_SKINS)
	assert_true(result["ok"])
	assert_eq(result["removed"], CUSTOM_SKINS)
	assert_false(DirAccess.dir_exists_absolute(SKINS))
	assert_true(FileAccess.file_exists(SAVES + "course_0.save"), "saved courses stay")


func test_deleting_an_empty_group_changes_nothing_and_writes_no_file() -> void:
	var result := PlayerDataStore.erase(PlayerDataStore.PREFERENCES)
	assert_true(result["ok"])
	assert_eq(result["removed"], 0)
	assert_false(FileAccess.file_exists(SETTINGS), "no settings file is created for nothing")
	# A second erase of the same empty group is just as harmless.
	result = PlayerDataStore.erase(PlayerDataStore.PREFERENCES)
	assert_true(result["ok"])
	assert_eq(result["removed"], 0)


# ---------------------------------------------------------------------------
# Deleting everything
# ---------------------------------------------------------------------------

func test_deleting_everything_leaves_a_fresh_install() -> void:
	_seed_everything()
	var result := PlayerDataStore.erase_all()
	assert_true(result["ok"], "no group failed: %s" % [result["errors"]])
	assert_gt(result["removed"], 0, "it reports what it removed")
	for file_name in DirAccess.get_files_at(SAVES):
		assert_false(str(file_name).ends_with(".save"), "no save file is left behind")
	assert_false(FileAccess.file_exists(SETTINGS), "the settings file is gone too")
	assert_false(FileAccess.file_exists(HISTORY))
	assert_false(FileAccess.file_exists(SNAPSHOT))
	assert_false(DirAccess.dir_exists_absolute(SKINS))
	assert_eq(PlayerDataStore.stored_group_count(), 0)
	assert_eq(PlayerDataStore.total_label(), "Nothing is stored on this device yet.")


func test_deleting_a_chosen_set_of_groups_keeps_the_rest() -> void:
	_seed_everything()
	var result := PlayerDataStore.erase_many([
		PlayerDataStore.BENCHMARK_REPORTS, PlayerDataStore.GOLFER_SKINS,
	])
	assert_true(result["ok"])
	assert_false(FileAccess.file_exists(HISTORY))
	assert_false(DirAccess.dir_exists_absolute(SKINS))
	assert_true(FileAccess.file_exists(SAVES + "course_0.save"))
	assert_true(FileAccess.file_exists(SETTINGS))
	assert_eq(PlayerDataStore.stored_group_count(), 3)


# ---------------------------------------------------------------------------
# The running game follows the deletion
# ---------------------------------------------------------------------------

const PERFORMANCE_FIELDS: Array[String] = [
	"graphics_preset", "terrain_quality", "grass_quality", "tree_occlusion_enabled",
	"water_quality", "wind_flag_quality", "animation_rate", "camera_update_rate",
	"golfer_update_rate", "fps_counter_enabled", "fps_counter_position",
	"fps_counter_size", "fps_counter_refresh",
]


func _performance_state() -> Dictionary:
	var fields := {}
	for field in PERFORMANCE_FIELDS:
		fields[field] = PerformanceSettings.get(field)
	return fields


func _put_performance_state(fields: Dictionary) -> void:
	for field in fields:
		PerformanceSettings.set(field, fields[field])


## Resetting preferences touches the live autoloads, which a scratch path never
## reaches through erase(): call the reset itself, then put the machine back.
func test_resetting_preferences_puts_the_running_game_on_defaults() -> void:
	var saved_audio := SoundManager.get_settings_data()
	var saved_performance := _performance_state()
	var tree := Engine.get_main_loop() as SceneTree
	var saved_scale: float = tree.root.content_scale_factor
	var saved_vsync := DisplayServer.window_get_vsync_mode()

	SoundManager.load_settings_data({
		"master_volume": 0.3, "sfx_volume": 0.2, "ambient_volume": 0.1, "is_muted": false,
	})
	PerformanceSettings.graphics_preset = PerformanceSettings.GraphicsPreset.HIGH
	PerformanceSettings.terrain_quality = PerformanceSettings.TerrainQuality.FAST
	PerformanceSettings.fps_counter_enabled = true
	PerformanceSettings.fps_counter_position = PerformanceSettings.FpsCounterPosition.BOTTOM_RIGHT
	tree.root.content_scale_factor = 1.4
	GameManager.invert_zoom_scroll = true
	GameManager.set_minimap_enabled(false)
	GameManager.set_colorblind_mode(ColorblindMode.Mode.DEUTERANOPIA)
	GameManager.set_camera_zoom_limits(1.0, 3.0)
	GameManager.player_skin_id = "custom"

	PlayerDataStore.reset_live_preferences()

	assert_almost_eq(SoundManager.master_volume, PlayerDataStore.DEFAULT_AUDIO["master_volume"], 0.001)
	assert_almost_eq(SoundManager.sfx_volume, PlayerDataStore.DEFAULT_AUDIO["sfx_volume"], 0.001)
	assert_almost_eq(SoundManager.ambient_volume, PlayerDataStore.DEFAULT_AUDIO["ambient_volume"], 0.001)
	assert_eq(SoundManager.is_muted, PlayerDataStore.DEFAULT_AUDIO["is_muted"], "the mixer is back on the shipped mute")
	assert_eq(PerformanceSettings.graphics_preset, PerformanceSettings.GraphicsPreset.AUTO,
		"graphics return to the device-aware Auto preset")
	assert_false(PerformanceSettings.fps_counter_enabled, "the FPS counter is off again")
	assert_eq(PerformanceSettings.fps_counter_position, PerformanceSettings.FpsCounterPosition.TOP_CENTER)
	assert_almost_eq(tree.root.content_scale_factor, 1.0, 0.001, "UI scale returns to 100%")
	assert_false(GameManager.invert_zoom_scroll)
	assert_true(GameManager.minimap_enabled)
	assert_eq(GameManager.colorblind_mode, ColorblindMode.Mode.OFF)
	assert_almost_eq(GameManager.camera_min_zoom, GameManager.CAMERA_MIN_ZOOM_DEFAULT, 0.001)
	assert_almost_eq(GameManager.camera_max_zoom, GameManager.CAMERA_MAX_ZOOM_DEFAULT, 0.001)
	assert_eq(GameManager.player_skin_id, "", "the owner goes back to their tier's skin")

	# Put the live game back for every test that runs after this one.
	SoundManager.load_settings_data(saved_audio)
	_put_performance_state(saved_performance)
	tree.root.content_scale_factor = saved_scale
	DisplayServer.window_set_vsync_mode(saved_vsync)


func test_resetting_benchmarks_forgets_the_last_run() -> void:
	PerformanceBenchmark.last_result = {"frame": {"sample_count": 90}, "score": {"overall": 70.0}}
	PlayerDataStore.reset_live_benchmarks()
	assert_eq(PerformanceBenchmark.last_result, {}, "the card has no run left to describe")
