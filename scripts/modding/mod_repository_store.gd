extends RefCounted
class_name ModRepositoryStore
## ModRepositoryStore - the player's list of Mod Repository Feeds.
##
## Kept in `user://mods/repositories.json` next to the mod loader's own
## lists, it says which feeds the Browse Mods screen shows and in what
## order. Feeds are plain URLs; the Official Repository - the game's own
## feed on GitHub, which offers the official environment mods and the
## examples - is added by default, the way a fresh install used to ship
## with those mods bundled.
##
## The list is the player's: any feed can be removed, the Official one
## included, and `restore_official_repository()` puts it back when wanted.
## A feed's display name is remembered once its JSON has been fetched
## successfully, so the screen can label it on an offline boot.
##
## Everything file-shaped is deliberately autoload-free and takes its root
## as a property (`store_root`), so tests can run a throwaway store the
## same way the command-line mod tool runs without one.

const STORE_FILE: String = "repositories.json"
const STORE_FORMAT: int = 1

## The game's own feed, served straight from the Golf Tycoon GitHub
## repository: the official environment mods and every example, packaged
## by `make repository` (see repository/README.md).
const OFFICIAL_REPOSITORY_URL: String = \
	"https://raw.githubusercontent.com/GolfTycoon/Golf-Tycoon/main/repository/official.json"
const OFFICIAL_REPOSITORY_NAME: String = "Golf Tycoon Official Repository"

var store_root: String = "user://mods"

## [{url, name, official}] in the order the player added them.
var _repositories: Array[Dictionary] = []


func _init(root: String = "") -> void:
	if not root.is_empty():
		store_root = root
	load_store()


# =============================================================================
# READING AND WRITING
# =============================================================================

func store_path() -> String:
	return store_root.path_join(STORE_FILE)


## Read the list, seeding the Official Repository on the first run or after
## a damaged file - the same promise load_order.json makes about the
## bundled mods it used to seed.
func load_store() -> void:
	_repositories.clear()
	var parsed: Variant = null
	if FileAccess.file_exists(store_path()):
		parsed = ModManifest.parse_json_quietly(FileAccess.get_file_as_string(store_path()))
	if parsed is Dictionary:
		_repositories = parse_repositories(parsed.get("repositories", []))
		return
	_repositories.append(_official_entry())
	_write_store()


## The repository list as plain data, or [] when `raw` is not a list of
## usable entries. Pure; also what the tests of the file format use.
static func parse_repositories(raw: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not (raw is Array):
		return result
	for entry in raw as Array:
		if not (entry is Dictionary):
			continue
		var url := normalize_url(str((entry as Dictionary).get("url", "")))
		if not ModRepositoryFeed.is_fetchable_url(url):
			continue
		var record := {
			"url": url,
			"name": str((entry as Dictionary).get("name", "")).strip_edges(),
			"official": bool((entry as Dictionary).get("official", false)),
		}
		if not has_url(result, url):
			result.append(record)
	return result


func _write_store() -> void:
	DirAccess.make_dir_recursive_absolute(store_root)
	var file := FileAccess.open(store_path(), FileAccess.WRITE)
	if file != null:
		file.store_string(JSON.stringify(
			{"version": STORE_FORMAT, "repositories": _repositories}, "\t") + "\n")


# =============================================================================
# THE LIST
# =============================================================================

func get_repositories() -> Array[Dictionary]:
	return _repositories.duplicate(true)


func repository_count() -> int:
	return _repositories.size()


func has_repository(url: String) -> bool:
	return has_url(_repositories, normalize_url(url))


static func has_url(repositories: Array[Dictionary], url: String) -> bool:
	for entry in repositories:
		if str(entry.get("url", "")) == url:
			return true
	return false


func repository_for(url: String) -> Dictionary:
	var normalized := normalize_url(url)
	for entry in _repositories:
		if str(entry.get("url", "")) == normalized:
			return entry
	return {}


func is_official(url: String) -> bool:
	return normalize_url(url) == normalize_url(OFFICIAL_REPOSITORY_URL)


func official_repository_present() -> bool:
	return has_repository(OFFICIAL_REPOSITORY_URL)


## Add a feed. Returns {ok, url, errors}; a bad or duplicate URL is refused
## with an explanation rather than silently ignored. Adding is not
## fetching: the feed's contents arrive when the screen refreshes it.
func add_repository(url: String) -> Dictionary:
	var result := {"ok": false, "url": "", "errors": []}
	var candidate := normalize_url(url)
	if candidate.is_empty():
		result["errors"] = ["Type or paste the address of a mod repository feed (an http(s) URL to its JSON)."]
		return result
	if not ModRepositoryFeed.is_fetchable_url(candidate):
		result["errors"] = ["'%s' is not an http(s) URL. Feed addresses point at a JSON file on the web." % candidate]
		return result
	result["url"] = candidate
	if has_repository(candidate):
		result["errors"] = ["That feed is already in the list."]
		return result
	_repositories.append({
		"url": candidate,
		"name": OFFICIAL_REPOSITORY_NAME if is_official(candidate) else "",
		"official": is_official(candidate),
	})
	_write_store()
	result["ok"] = true
	return result


## Remove a feed, the Official one included: the list is the player's.
## Returns {ok, errors}.
func remove_repository(url: String) -> Dictionary:
	var normalized := normalize_url(url)
	for index in _repositories.size():
		if str(_repositories[index].get("url", "")) == normalized:
			_repositories.remove_at(index)
			_write_store()
			return {"ok": true, "errors": []}
	return {"ok": false, "errors": ["That feed is not in the list."]}


## Put the Official Repository back (a no-op when it is already there).
func restore_official_repository() -> bool:
	if official_repository_present():
		return false
	_repositories.append(_official_entry())
	_write_store()
	return true


## Remember what a feed's JSON called itself, so it keeps its label when it
## cannot be reached. Returns whether anything changed.
func note_feed_name(url: String, feed_name: String) -> bool:
	var record := repository_for(url)
	if record.is_empty():
		return false
	var cleaned := feed_name.strip_edges()
	if cleaned.is_empty() or str(record.get("name", "")) == cleaned:
		return false
	record["name"] = cleaned
	_write_store()
	return true


static func _official_entry() -> Dictionary:
	return {"url": OFFICIAL_REPOSITORY_URL, "name": OFFICIAL_REPOSITORY_NAME, "official": true}


## Whitespace off the ends; everything else is taken literally, because a
## feed URL is a file address, not a search box.
static func normalize_url(url: String) -> String:
	return url.strip_edges()


## What the Add feed box suggests before anything is typed.
static func add_prompt() -> String:
	return "https://example.com/my-mods.json"
