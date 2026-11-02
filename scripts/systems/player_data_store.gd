extends RefCounted
class_name PlayerDataStore
## PlayerDataStore - the one catalogue of what Golf Tycoon keeps on this device.
##
## Everything the game writes under `user://` belongs to exactly one group here:
## saved courses, preferences, career records, benchmark reports and custom
## golfer skins. The Settings screen's Data page reads this catalogue to say
## what is stored, and deletes one group - or all of them - through it, so no
## screen has to guess at file names.
##
## Deleting a group also puts the running game back on that group's defaults:
## preferences return to the shipped settings, the career shelf empties and the
## golfer skins library reloads without the deleted skins. A fresh install is
## what is left after `erase_all()`.
##
## Mods are deliberately not a group. A mod that is loaded cannot be removed
## while it runs, and the Mods screen already uninstalls each one safely, so the
## Data page points there instead of half-deleting a library.

const SAVED_COURSES := "saved_courses"
const PREFERENCES := "preferences"
const CAREER := "career"
const BENCHMARK_REPORTS := "benchmark_reports"
const GOLFER_SKINS := "golfer_skins"

## Order the Data page lists them in: the biggest thing first, the art last.
const GROUP_IDS: Array[String] = [
	SAVED_COURSES, PREFERENCES, CAREER, BENCHMARK_REPORTS, GOLFER_SKINS,
]

const SAVE_EXTENSION := ".save"
## Sections of settings.cfg that hold a preference. The career sections are
## separate on purpose: resetting the mixer must never wipe the trophy case.
const PREFERENCE_SECTIONS: Array[String] = [
	"audio", "display", "controls", "camera", "gameplay", "graphics",
]
const CAREER_SECTIONS: Array[String] = ["achievements", "tutorial"]
## The shipped audio mix, the same one a first launch starts with.
const DEFAULT_AUDIO := {
	"master_volume": 0.8,
	"sfx_volume": 1.0,
	"ambient_volume": 0.6,
	"is_muted": true,
}

## Defaults mirror the paths the rest of the game writes with. They are static
## vars rather than constants so a test can point the store at a scratch folder
## and never touch the real player's files.
const DEFAULT_SAVES_DIR: String = "user://saves/"
const DEFAULT_SETTINGS_PATH: String = "user://settings.cfg"
const DEFAULT_BENCHMARK_HISTORY_PATH: String = "user://benchmark_history.json"
const DEFAULT_ECONOMIC_SNAPSHOT_PATH: String = "user://economic_snapshots.json"
const DEFAULT_GOLFER_SKINS_DIR: String = "user://golfer_skins"

static var saves_dir: String = DEFAULT_SAVES_DIR
static var settings_path: String = DEFAULT_SETTINGS_PATH
static var benchmark_history_path: String = DEFAULT_BENCHMARK_HISTORY_PATH
static var economic_snapshot_path: String = DEFAULT_ECONOMIC_SNAPSHOT_PATH
static var golfer_skins_dir: String = DEFAULT_GOLFER_SKINS_DIR

## ── Catalogue ──────────────────────────────────────────────────────────────

static func group_title(id: String) -> String:
	match id:
		SAVED_COURSES: return "SAVED COURSES"
		PREFERENCES: return "PREFERENCES"
		CAREER: return "CAREER RECORDS"
		BENCHMARK_REPORTS: return "BENCHMARK REPORTS"
		GOLFER_SKINS: return "CUSTOM GOLFER SKINS"
	return id.to_upper()


## The group's name in a sentence ("Saved courses deleted from this device.").
static func group_name(id: String) -> String:
	match id:
		SAVED_COURSES: return "Saved courses"
		PREFERENCES: return "Preferences"
		CAREER: return "Career records"
		BENCHMARK_REPORTS: return "Benchmark reports"
		GOLFER_SKINS: return "Custom golfer skins"
	return id


static func group_description(id: String) -> String:
	match id:
		SAVED_COURSES:
			return "Every checkpoint and the automatic save: your companies, courses, money and calendar."
		PREFERENCES:
			return "Audio, display, controls and camera settings for this device."
		CAREER:
			return "Achievements unlocked across every company, and the tutorial flag."
		BENCHMARK_REPORTS:
			return "Past device benchmark runs and the diagnostic snapshot."
		GOLFER_SKINS:
			return "The golfer skins you painted and saved to this device."
	return ""


## What the group's button says. The count makes the size of the deletion
## clear before the confirmation even opens.
static func group_action(id: String, count: int) -> String:
	match id:
		SAVED_COURSES:
			return "Delete Saved Courses" if count <= 0 else "Delete %d Saved Course%s" % [count, "" if count == 1 else "s"]
		PREFERENCES:
			return "Reset Preferences"
		CAREER:
			return "Delete Career Records"
		BENCHMARK_REPORTS:
			return "Delete Benchmark Reports"
		GOLFER_SKINS:
			return "Delete Custom Skins" if count <= 0 else "Delete %d Custom Skin%s" % [count, "" if count == 1 else "s"]
	return "Delete"


static func group_confirm_title(id: String) -> String:
	match id:
		SAVED_COURSES: return "Delete saved courses?"
		PREFERENCES: return "Reset preferences?"
		CAREER: return "Delete career records?"
		BENCHMARK_REPORTS: return "Delete benchmark reports?"
		GOLFER_SKINS: return "Delete custom golfer skins?"
	return "Delete this data?"


static func group_confirm_message(id: String, count: int) -> String:
	match id:
		SAVED_COURSES:
			if count <= 0:
				return "No saved courses are stored on this device."
			if count == 1:
				return "The saved course on this device will be permanently removed."
			return "All %d saved courses - the automatic save and every checkpoint - will be permanently removed from this device." % count
		PREFERENCES:
			return "Audio, display, control and camera preferences go back to their shipped defaults. Saved courses and career records stay."
		CAREER:
			return "Every achievement and the tutorial flag will be cleared. Saved courses and preferences stay."
		BENCHMARK_REPORTS:
			return "Every benchmark run on the shelf and the diagnostic snapshot will be removed. Saved courses stay."
		GOLFER_SKINS:
			return "Every custom skin saved on this device is removed; the skins shipped with the game stay. A golfer wearing one falls back to a shipped skin."
	return ""


## ── What is stored ─────────────────────────────────────────────────────────

## {id, count, present, label}: how many of the group's things exist, whether
## anything is stored at all, and a line for the Data page.
static func usage(id: String) -> Dictionary:
	match id:
		SAVED_COURSES:
			var saves := _save_files()
			var saves_label := "No saved courses."
			if saves.size() == 1:
				saves_label = "1 saved course."
			elif saves.size() > 1:
				saves_label = "%d saved courses." % saves.size()
			return _usage(id, saves.size(), not saves.is_empty(), saves_label)
		PREFERENCES:
			var preferences := _preference_value_count()
			var preferences_label := "Using the shipped defaults."
			if preferences == 1:
				preferences_label = "1 preference saved."
			elif preferences > 1:
				preferences_label = "%d preferences saved." % preferences
			return _usage(id, preferences, preferences > 0, preferences_label)
		CAREER:
			var state := _career_usage()
			var count := int(state["achievements"]) + (1 if bool(state["tutorial"]) else 0)
			var parts: Array[String] = []
			if int(state["achievements"]) == 1:
				parts.append("1 achievement")
			elif int(state["achievements"]) > 1:
				parts.append("%d achievements" % int(state["achievements"]))
			if bool(state["tutorial"]):
				parts.append("tutorial finished")
			var career_label := "No career records yet."
			if not parts.is_empty():
				career_label = " · ".join(parts) + "."
			return _usage(id, count, count > 0, career_label)
		BENCHMARK_REPORTS:
			var runs := _benchmark_run_count()
			var snapshot := FileAccess.file_exists(economic_snapshot_path)
			var reports_label := "No benchmark reports."
			if runs == 1:
				reports_label = "1 benchmark report on the shelf."
			elif runs > 1:
				reports_label = "%d benchmark reports on the shelf." % runs
			elif snapshot:
				reports_label = "A diagnostic snapshot is stored."
			return _usage(id, runs, runs > 0 or snapshot, reports_label)
		GOLFER_SKINS:
			var skins := _skin_folders().size()
			var skins_label := "No custom golfer skins."
			if skins == 1:
				skins_label = "1 custom golfer skin."
			elif skins > 1:
				skins_label = "%d custom golfer skins." % skins
			return _usage(id, skins, skins > 0, skins_label)
	return _usage(id, 0, false, "Nothing stored.")


## "Nothing is stored yet." or "3 of 5 data groups hold something on this
## device." The long list belongs to the cards below, not this line.
static func total_label() -> String:
	var stored := stored_group_count()
	if stored == 0:
		return "Nothing is stored on this device yet."
	return "%d of %d data groups hold something on this device." % [stored, GROUP_IDS.size()]


static func stored_group_count() -> int:
	var stored := 0
	for id in GROUP_IDS:
		if bool(usage(id)["present"]):
			stored += 1
	return stored


static func anything_stored() -> bool:
	return stored_group_count() > 0


## ── Deleting ───────────────────────────────────────────────────────────────

## Remove one group and put the running game back on its defaults.
## Result: {ok, removed, errors} - `removed` counts the things deleted (saves,
## preference values, achievements, runs, skins), not the files they lived in.
static func erase(id: String) -> Dictionary:
	return erase_many([id])


## Remove several groups in one pass. Preferences and career records share
## settings.cfg, so both are erased before any defaults are applied.
static func erase_many(ids: Array) -> Dictionary:
	var errors: Array[String] = []
	var removed := 0
	var erased: Array[String] = []
	for raw_id in ids:
		var id := str(raw_id)
		if id in erased:
			continue
		var result := _erase_one(id)
		removed += int(result.get("removed", 0))
		for error in result.get("errors", []):
			errors.append(str(error))
		erased.append(id)
	for id in erased:
		_apply_defaults(id)
	return {"ok": errors.is_empty(), "removed": removed, "errors": errors}


## Delete every group: the device is left as a fresh install would leave it.
static func erase_all() -> Dictionary:
	return erase_many(GROUP_IDS)


static func _erase_one(id: String) -> Dictionary:
	match id:
		SAVED_COURSES:
			return _erase_files(_save_files())
		PREFERENCES:
			return _erase_sections(PREFERENCE_SECTIONS)
		CAREER:
			return _erase_sections(CAREER_SECTIONS)
		BENCHMARK_REPORTS:
			return _erase_benchmarks()
		GOLFER_SKINS:
			return _erase_skins()
	return {"ok": false, "removed": 0, "errors": ["Unknown data group: " + id]}


static func _erase_files(paths: Array[String]) -> Dictionary:
	var errors: Array[String] = []
	var removed := 0
	for path in paths:
		if _remove_file(path):
			removed += 1
		else:
			errors.append("Could not delete %s." % path)
	return {"ok": errors.is_empty(), "removed": removed, "errors": errors}


## Erase whole sections of settings.cfg. The file itself is removed once no
## section is left, so a full erase leaves no settings file behind.
static func _erase_sections(sections: Array[String]) -> Dictionary:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return {"ok": true, "removed": 0, "errors": []}
	var errors: Array[String] = []
	var removed := 0
	for section in sections:
		if not config.has_section(section):
			continue
		removed += maxi(config.get_section_keys(section).size(), 1)
		config.erase_section(section)
	if removed > 0:
		if config.get_sections().is_empty():
			if not _remove_file(settings_path):
				errors.append("Could not delete %s." % settings_path)
		elif config.save(settings_path) != OK:
			errors.append("Could not write %s." % settings_path)
	return {"ok": errors.is_empty(), "removed": removed, "errors": errors}


static func _erase_benchmarks() -> Dictionary:
	var errors: Array[String] = []
	var removed := _benchmark_run_count()
	if FileAccess.file_exists(economic_snapshot_path):
		removed += 1
	for path in [benchmark_history_path, economic_snapshot_path]:
		if not _remove_file(path):
			errors.append("Could not delete %s." % path)
	return {"ok": errors.is_empty(), "removed": removed, "errors": errors}


static func _erase_skins() -> Dictionary:
	var removed := _skin_folders().size()
	var errors: Array[String] = []
	if DirAccess.dir_exists_absolute(golfer_skins_dir):
		if not _remove_tree(golfer_skins_dir):
			errors.append("Could not delete %s." % golfer_skins_dir)
	return {"ok": errors.is_empty(), "removed": removed, "errors": errors}

## ── Defaults for the running game ──────────────────────────────────────────
## Applied only while the store points at the player's real files: a test that
## aimed the store at a scratch folder must not reset the live game.

static func _apply_defaults(id: String) -> void:
	match id:
		SAVED_COURSES:
			if saves_dir == DEFAULT_SAVES_DIR:
				SaveManager.current_save_name = ""
		PREFERENCES:
			if settings_path == DEFAULT_SETTINGS_PATH:
				reset_live_preferences()
		CAREER:
			if settings_path == DEFAULT_SETTINGS_PATH:
				reset_live_career()
		BENCHMARK_REPORTS:
			if benchmark_history_path == DEFAULT_BENCHMARK_HISTORY_PATH:
				reset_live_benchmarks()
		GOLFER_SKINS:
			if golfer_skins_dir == DEFAULT_GOLFER_SKINS_DIR:
				reset_live_skins()


## Put the running game back on the shipped preference defaults: the mixer,
## graphics preset, FPS counter, UI scale, VSync, course HUD, colour palette,
## camera panning and limits, key bindings and the owner's skin choice.
## Nothing is written to disk - the delete path has just removed the file.
static func reset_live_preferences() -> void:
	var tree := Engine.get_main_loop() as SceneTree
	if tree:
		var screen := tree.root.get_node_or_null("Screen")
		if screen != null:
			# Back to automatic sizing: the detected default for this device,
			# not a hard 100% (which would be wrong on a high-DPI display).
			screen.call("reset_ui_scale", false)
		else:
			tree.root.content_scale_factor = 1.0
	SoundManager.load_settings_data(DEFAULT_AUDIO)
	PerformanceSettings.load_from_config(ConfigFile.new())
	InputBindings.reset_all(false)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	GameManager.set_minimap_enabled(true)
	GameManager.set_colorblind_mode(ColorblindMode.Mode.OFF)
	GameManager.set_edge_pan_enabled(true)
	GameManager.invert_zoom_scroll = false
	GameManager.set_camera_zoom_limits(
		GameManager.CAMERA_MIN_ZOOM_DEFAULT, GameManager.CAMERA_MAX_ZOOM_DEFAULT)
	GameManager.player_skin_id = ""


## Empty the running game's career shelf to match the deleted sections.
static func reset_live_career() -> void:
	AchievementStore.clear()
	var manager = SaveManager.milestone_manager
	if manager and manager.has_method("refresh_achievements"):
		manager.refresh_achievements()


## Forget the last benchmark run, so the Display card has nothing to describe.
static func reset_live_benchmarks() -> void:
	PerformanceBenchmark.last_result = {}


## Reload the skins library without the deleted custom skins.
static func reset_live_skins() -> void:
	# Only a choice that pointed at one of the deleted skins needs clearing;
	# a shipped skin the player picked stays their choice. The stored id is
	# harmless either way (GolferSkinLibrary falls back when a skin is
	# missing), so nothing is written back here - that would recreate the
	# preference a full erase just deleted.
	if GolferSkins.library.is_user_skin(GameManager.player_skin_id):
		GameManager.player_skin_id = ""
	GolferSkins.reload()


## Put the store back on the player's real files (a test's teardown).
static func restore_default_paths() -> void:
	saves_dir = DEFAULT_SAVES_DIR
	settings_path = DEFAULT_SETTINGS_PATH
	benchmark_history_path = DEFAULT_BENCHMARK_HISTORY_PATH
	economic_snapshot_path = DEFAULT_ECONOMIC_SNAPSHOT_PATH
	golfer_skins_dir = DEFAULT_GOLFER_SKINS_DIR


## ── Reading the device ─────────────────────────────────────────────────────

static func _usage(id: String, count: int, present: bool, label: String) -> Dictionary:
	return {"id": id, "count": count, "present": present, "label": label}


static func _save_files() -> Array[String]:
	var paths: Array[String] = []
	if not DirAccess.dir_exists_absolute(saves_dir):
		return paths
	for file_name in DirAccess.get_files_at(saves_dir):
		if str(file_name).ends_with(SAVE_EXTENSION):
			paths.append(_join(saves_dir, str(file_name)))
	paths.sort()
	return paths


static func _preference_value_count() -> int:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return 0
	var count := 0
	for section in PREFERENCE_SECTIONS:
		if config.has_section(section):
			count += config.get_section_keys(section).size()
	return count


static func _career_usage() -> Dictionary:
	var config := ConfigFile.new()
	if config.load(settings_path) != OK:
		return {"achievements": 0, "tutorial": false}
	var unlocked: Variant = config.get_value("achievements", "unlocked", {})
	var achievements := 0
	if unlocked is Dictionary:
		achievements = (unlocked as Dictionary).size()
	return {
		"achievements": achievements,
		"tutorial": bool(config.get_value("tutorial", "completed", false)),
	}


## How many runs the shelf file holds. A file that cannot be read still counts
## as one report, so it is still reported and can still be deleted.
static func _benchmark_run_count() -> int:
	if not FileAccess.file_exists(benchmark_history_path):
		return 0
	var file := FileAccess.open(benchmark_history_path, FileAccess.READ)
	if file == null:
		return 1
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	file.close()
	if not (parsed is Dictionary):
		return 1
	var runs: Variant = (parsed as Dictionary).get("runs", [])
	return (runs as Array).size() if runs is Array and not (runs as Array).is_empty() else 1


static func _skin_folders() -> Array[String]:
	var folders: Array[String] = []
	if not DirAccess.dir_exists_absolute(golfer_skins_dir):
		return folders
	for folder in DirAccess.get_directories_at(golfer_skins_dir):
		if not str(folder).begins_with("."):
			folders.append(str(folder))
	folders.sort()
	return folders


# ── Filesystem helpers ─────────────────────────────────────────────────────

static func _join(dir: String, entry: String) -> String:
	return dir.trim_suffix("/").path_join(entry)


static func _remove_file(path: String) -> bool:
	if not FileAccess.file_exists(path):
		return true
	return DirAccess.remove_absolute(path) == OK


## Delete a folder and everything under it, returning true once it is gone.
static func _remove_tree(path: String) -> bool:
	if not DirAccess.dir_exists_absolute(path):
		return true
	var dir := DirAccess.open(path)
	if dir == null:
		return false
	dir.list_dir_begin()
	var entry := dir.get_next()
	while not entry.is_empty():
		if entry != "." and entry != "..":
			var full := _join(path, entry)
			if dir.current_is_dir():
				_remove_tree(full)
			else:
				DirAccess.remove_absolute(full)
		entry = dir.get_next()
	dir.list_dir_end()
	DirAccess.remove_absolute(path)
	return not DirAccess.dir_exists_absolute(path)
