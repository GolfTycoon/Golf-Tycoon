extends Node
class_name ModRepositoryDownloader
## ModRepositoryDownloader - fetches Mod Repository Feeds and the mod zips
## they offer, over plain HTTP(S).
##
## Two jobs, both callback-shaped because network answers arrive whenever
## they arrive:
##
##   * fetch_feed(url, on_done)        - GET the feed's JSON and parse it
##                                       into a ModRepositoryFeed;
##   * download_and_install(entry, on_done) - GET a feed entry's zip, save
##                                       it to a scratch folder, and hand
##                                       it to ModPackage.install_zip, the
##                                       exact installer the Mods screen's
##                                       "Install ZIP" uses. A downloaded
##                                       mod therefore lands where any
##                                       player-installed mod lands
##                                       (`user://mods/installed/`), and
##                                       nothing about it is special.
##
## Every callback receives a result Dictionary with an `ok` flag and an
## `errors` array of player-readable lines; nothing here pushes engine
## errors, because a feed that will not answer is an expected outcome, not
## a crash. Requests are plain HTTPRequest nodes, one per call, freed when
## done; `fetch_override` replaces the whole network layer for tests.
##
## Parsing, sizing and installing a download reuse the mod package code, so
## the same limits and the same zip-slip rails apply to a feed download as
## to a zip a player picked by hand.

## Where downloaded zips rest before they are unpacked. Scratch space: the
## file is removed as soon as the install attempt is over.
const DOWNLOAD_ROOT: String = "user://mods/downloads"

## Seconds before a request that has not answered is given up on.
const REQUEST_TIMEOUT: float = 20.0

## Set in tests to serve requests without a network:
## `func(url: String, on_done: Callable) -> void`, with `on_done` given the
## same {ok, status, bytes, errors} Dictionary `fetch_bytes` produces.
var fetch_override: Callable = Callable()

var download_root: String = DOWNLOAD_ROOT
var install_root: String = "user://mods/installed"

## Live HTTP requests by URL, for progress questions while a download is
## under way ({url: HTTPRequest}).
var _active: Dictionary = {}


## 0..1 for a request currently under way, or -1 when nothing about `url`
## is in flight or its size is not known yet.
func progress_of(url: String) -> float:
	var request: HTTPRequest = _active.get(url, null)
	if request == null or not is_instance_valid(request):
		return -1.0
	var total := request.get_body_size()
	if total <= 0:
		return -1.0
	return clampf(float(request.get_downloaded_bytes()) / float(total), 0.0, 1.0)


func is_fetching(url: String) -> bool:
	var request: HTTPRequest = _active.get(url, null)
	return request != null and is_instance_valid(request)


# =============================================================================
# FEEDS
# =============================================================================

## GET a feed and parse it. `on_done` receives
## {ok, url, feed: ModRepositoryFeed, errors}.
func fetch_feed(url: String, on_done: Callable) -> void:
	fetch_bytes(url, func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			on_done.call({"ok": false, "url": url, "feed": null,
				"errors": result.get("errors", [])})
			return
		var feed := ModRepositoryFeed.parse(bytes_text(result), url)
		var errors: Array[String] = []
		if not feed.is_valid():
			errors.append_array(feed.errors)
		on_done.call({"ok": feed.is_valid(), "url": url, "feed": feed, "errors": errors}))


# =============================================================================
# MOD DOWNLOADS
# =============================================================================

## Whether a download for `entry` is plausible before starting one: the
## entry names a size and it is beyond what any mod zip may be.
static func entry_size_is_impossible(entry: Dictionary) -> bool:
	var size := int(entry.get("size_bytes", 0))
	return size > 0 and size > ModPackage.MAX_ZIP_BYTES


## Download the zip a feed entry points at and install it as an ordinary
## player-installed mod. `on_done` receives
## {ok, mod_id, directory, entry, errors}. Installing never enables: the
## mod waits unticked in the Mods screen's library, like any installed zip.
func download_and_install(entry: Dictionary, on_done: Callable) -> void:
	var url := str(entry.get("download_url", ""))
	if url.is_empty() or not ModRepositoryFeed.is_downloadable_url(url):
		on_done.call({"ok": false, "mod_id": str(entry.get("id", "")), "entry": entry,
			"errors": ["That entry has no usable download_url."]})
		return
	if entry_size_is_impossible(entry):
		var said_mb: int = int(float(int(entry.get("size_bytes", 0))) / 1048576.0)
		var limit_mb: int = int(float(ModPackage.MAX_ZIP_BYTES) / 1048576.0)
		on_done.call({"ok": false, "mod_id": str(entry.get("id", "")), "entry": entry,
			"errors": ["The feed says it is %d MB; a mod zip may be at most %d MB."
				% [said_mb, limit_mb]]})
		return
	fetch_bytes(url, func(result: Dictionary) -> void:
		if not bool(result.get("ok", false)):
			on_done.call({"ok": false, "mod_id": str(entry.get("id", "")), "entry": entry,
				"errors": result.get("errors", [])})
			return
		var outcome := _install_downloaded_bytes(entry, result.get("bytes", PackedByteArray()))
		on_done.call(outcome))


func _install_downloaded_bytes(entry: Dictionary, bytes: PackedByteArray) -> Dictionary:
	var mod_id := str(entry.get("id", ""))
	var scratch := download_root.path_join("mod-%s.zip" % mod_id)
	var errors: Array[String] = []
	DirAccess.make_dir_recursive_absolute(download_root)
	var file := FileAccess.open(scratch, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "mod_id": mod_id, "entry": entry,
			"errors": ["Could not save the download to scratch space."]}
	file.store_buffer(bytes)
	file.close()
	var installed: Dictionary = ModPackage.install_zip(scratch, install_root)
	DirAccess.remove_absolute(scratch)
	if not bool(installed.get("ok", false)):
		for error in installed.get("errors", []):
			errors.append(str(error))
		return {"ok": false, "mod_id": mod_id, "entry": entry, "errors": errors}
	return {"ok": true, "mod_id": str(installed.get("mod_id", mod_id)),
		"directory": str(installed.get("directory", "")), "entry": entry, "errors": errors}


# =============================================================================
# THE NETWORK LAYER
# =============================================================================

## GET any URL as bytes. `on_done` receives {ok, status, bytes, errors}.
func fetch_bytes(url: String, on_done: Callable) -> void:
	if fetch_override.is_valid():
		fetch_override.call(url, on_done)
		return
	_http_fetch(url, on_done)


func _http_fetch(url: String, on_done: Callable) -> void:
	var request := HTTPRequest.new()
	request.timeout = REQUEST_TIMEOUT
	request.accept_gzip = true
	add_child(request)
	_active[url] = request
	request.request_completed.connect(func(result: int, response_code: int,
			_headers: PackedStringArray, body: PackedByteArray) -> void:
		_active.erase(url)
		request.queue_free()
		if result != HTTPRequest.RESULT_SUCCESS:
			on_done.call({"ok": false, "status": 0, "bytes": PackedByteArray(),
				"errors": [_network_error(result)]})
			return
		if response_code < 200 or response_code >= 300:
			on_done.call({"ok": false, "status": response_code, "bytes": PackedByteArray(),
				"errors": ["The server answered %d." % response_code]})
			return
		on_done.call({"ok": true, "status": response_code, "bytes": body, "errors": []}))
	var error := request.request(url)
	if error != OK:
		# Failed to even start (bad URL, no network stack): the request will
		# not complete, so answer now. The node frees itself on completion;
		# a never-started one is freed here.
		_active.erase(url)
		request.queue_free()
		on_done.call({"ok": false, "status": 0, "bytes": PackedByteArray(),
			"errors": ["Could not start the request (%s)." % _request_error(error)]})


## The bytes of a fetch result as text (feeds).
static func bytes_text(result: Dictionary) -> String:
	var bytes: PackedByteArray = result.get("bytes", PackedByteArray())
	return bytes.get_string_from_utf8()


## A player-readable line for a failed HTTPRequest (the RESULT_* codes),
## naming what to check rather than quoting an engine enum.
static func _network_error(result: int) -> String:
	match result:
		HTTPRequest.RESULT_CANT_RESOLVE:
			return "That address could not be resolved - check the spelling and your connection."
		HTTPRequest.RESULT_CANT_CONNECT:
			return "Could not connect to the server - check your connection."
		HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR:
			return "The server's security certificate could not be verified."
		HTTPRequest.RESULT_REQUEST_FAILED:
			return "The request failed part-way through."
		HTTPRequest.RESULT_DOWNLOAD_FILE_CANT_OPEN, HTTPRequest.RESULT_DOWNLOAD_FILE_WRITE_ERROR:
			return "Could not save the download to disk."
		HTTPRequest.RESULT_TIMEOUT:
			return "The server did not answer in time."
		_:
			return "The request failed (error %d)." % result


static func _request_error(error: Error) -> String:
	match error:
		ERR_INVALID_PARAMETER:
			return "the URL is not valid"
		ERR_UNAUTHORIZED:
			return "the URL scheme is not supported"
		_:
			return "error %d" % error
