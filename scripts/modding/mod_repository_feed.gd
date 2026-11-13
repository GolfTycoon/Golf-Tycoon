extends RefCounted
class_name ModRepositoryFeed
## ModRepositoryFeed - one Mod Repository Feed: a JSON document on the web
## that lists the mods a repository offers for download.
##
## A feed is a plain static JSON file, so anybody can run one: any web host
## (GitHub Pages, a bucket, a home server) that can serve JSON and mod zips
## is a Golf Tycoon mod repository. The shape is deliberately small:
##
##     {
##       "format_version": 1,
##       "name": "My mod repository",
##       "description": "Optional one-liner.",
##       "mods": [
##         {
##           "id": "yourname.cool_mod",
##           "name": "Cool Mod",
##           "version": "1.2.0",
##           "author": "yourname",
##           "description": "What it does.",
##           "download_url": "https://example.com/mods/cool_mod-1.2.0.zip",
##           "size_bytes": 24152,
##           "api_version": 1
##         }
##       ]
##     }
##
## The feed is only a catalogue: it says what is on offer and where to get
## it. Everything that decides whether a mod may load - the manifest inside
## its zip, the API and game version gates, the player's tick - is checked
## later, by the same loader that reads any other mod. The Official
## Repository is exactly such a file, served from the game's GitHub
## repository (see repository/README.md), and players can add feeds of
## their own - or anybody's - on the Browse Mods screen.
##
## Parsing is strict where the loader would be: an entry without a usable
## mod id or a download URL is dropped and explained in `entry_errors`
## rather than listed half-blind. Malformed JSON is an expected, reportable
## outcome - strangers' files - so parsing never pushes engine errors.

## The feed format this build of the game reads.
const FORMAT_VERSION: int = 1

## The name shown when a feed does not name itself.
const FALLBACK_NAME: String = "Unnamed repository"

var name: String = FALLBACK_NAME
var description: String = ""
var homepage: String = ""
## The URL the feed was fetched from, set by the downloader; the feed file
## itself does not have to say where it lives.
var source_url: String = ""
var errors: Array[String] = []
## What became of the `mods` entries: every one that parsed, in file order.
var entries: Array[Dictionary] = []
## One line per dropped entry, for the Browse Mods screen to show.
var entry_errors: Array[String] = []


func is_valid() -> bool:
	return errors.is_empty()


func entry_count() -> int:
	return entries.size()


func has_entry(mod_id: String) -> bool:
	for entry in entries:
		if str(entry.get("id", "")) == mod_id:
			return true
	return false


func entry_for(mod_id: String) -> Dictionary:
	for entry in entries:
		if str(entry.get("id", "")) == mod_id:
			return entry
	return {}


# =============================================================================
# PARSING
# =============================================================================

## Parse feed JSON. Never null and never engine-noisy: a document that will
## not parse comes back as an invalid feed carrying the reason, so the
## Browse Mods screen can show it next to the repository that served it.
static func parse(text: String, origin_url: String = "") -> ModRepositoryFeed:
	var feed := ModRepositoryFeed.new()
	feed.source_url = origin_url
	var parsed: Variant = ModManifest.parse_json_quietly(text)
	if parsed == null:
		feed.errors.append("The feed is not valid JSON.")
		return feed
	if not (parsed is Dictionary):
		feed.errors.append("The feed must be a JSON object.")
		return feed
	feed._read(parsed as Dictionary)
	return feed


func _read(data: Dictionary) -> void:
	var format_version := int(data.get("format_version", 0))
	if format_version != FORMAT_VERSION:
		errors.append("format_version must be %d (found %d)." % [FORMAT_VERSION, format_version])
	name = str(data.get("name", "")).strip_edges()
	if name.is_empty():
		name = FALLBACK_NAME
	description = str(data.get("description", "")).strip_edges()
	homepage = str(data.get("homepage", "")).strip_edges()
	var seen: Dictionary = {}
	if not data.has("mods"):
		errors.append("The feed has no 'mods' list.")
		return
	var raw_mods: Variant = data.get("mods", [])
	if raw_mods is Array:
		for raw_entry in raw_mods as Array:
			var entry := _read_entry(raw_entry)
			if entry.is_empty():
				continue
			var mod_id := str(entry["id"])
			if seen.has(mod_id):
				entry_errors.append("%s: listed twice; keeping the first." % mod_id)
				continue
			seen[mod_id] = true
			entries.append(entry)
	else:
		errors.append("'mods' must be a list of mod entries.")


## One catalogue entry, or {} when it cannot be used (the reason lands in
## entry_errors). An entry is only a pointer to a zip; fields beyond the id
## and the download URL are display helpers the manifest inside the zip
## will confirm anyway.
func _read_entry(raw: Variant) -> Dictionary:
	if not (raw is Dictionary):
		entry_errors.append("A mod entry must be a JSON object; skipped.")
		return {}
	var data := raw as Dictionary
	var mod_id := str(data.get("id", "")).strip_edges()
	var download_url := str(data.get("download_url", "")).strip_edges()
	var entry_name := str(data.get("name", "")).strip_edges()
	if mod_id.is_empty() or not ModManifest.is_valid_mod_id(mod_id):
		entry_errors.append("%s: '%s' is not a valid mod id; skipped."
			% [entry_name if not entry_name.is_empty() else "unnamed entry", mod_id])
		return {}
	if not is_downloadable_url(download_url):
		entry_errors.append("%s: its download_url is missing or not an http(s) address; skipped." % mod_id)
		return {}
	var entry := {
		"id": mod_id,
		"name": entry_name if not entry_name.is_empty() else mod_id,
		"download_url": download_url,
		"version": str(data.get("version", "")).strip_edges(),
		"author": str(data.get("author", "")).strip_edges(),
		"description": str(data.get("description", "")).strip_edges(),
		"api_version": int(data.get("api_version", 0)),
		"size_bytes": maxi(0, int(data.get("size_bytes", 0))),
	}
	return entry


## The URLs a feed may point at: plain http(s), no tricks. A relative or
## scheme-less address would silently depend on where the feed was hosted.
static func is_downloadable_url(url: String) -> bool:
	var candidate := url.strip_edges().to_lower()
	return candidate.begins_with("https://") or candidate.begins_with("http://")


## Whether `url` is a feed address the game will try to fetch.
static func is_fetchable_url(url: String) -> bool:
	return is_downloadable_url(url)


## Display order for a feed's entries: by name the way a player reads it
## (ignoring case, "Pack 2" before "Pack 10"), then by id. Pure.
static func entry_before(a: Dictionary, b: Dictionary) -> bool:
	var a_id := str(a.get("id", ""))
	var b_id := str(b.get("id", ""))
	var a_name := str(a.get("name", ""))
	var b_name := str(b.get("name", ""))
	var by_name: int = (a_name if not a_name.is_empty() else a_id).naturalnocasecmp_to(
		b_name if not b_name.is_empty() else b_id)
	if by_name != 0:
		return by_name < 0
	return a_id < b_id
