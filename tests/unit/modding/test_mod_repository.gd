extends GameTest
## The Mod Repository machinery: the player's feed list (ModRepositoryStore),
## the feed JSON format (ModRepositoryFeed) and the downloader that turns a
## feed entry into an installed mod (ModRepositoryDownloader). The network
## layer is replaced with a local fetcher, so everything here is hermetic -
## the glue that would really speak HTTP is two calls away from code that is
## exercised directly.
## (scripts/modding/mod_repository_*.gd)

const ROOT := "user://ut_mod_repository"

var store: ModRepositoryStore = null
var downloader: ModRepositoryDownloader = null

## url -> {ok, status, bytes, errors}: the local "server" the fetch override
## answers every request with.
var _served: Dictionary = {}


func before_each() -> void:
	super()
	_cleanup()
	store = ModRepositoryStore.new(ROOT.path_join("store"))
	downloader = ModRepositoryDownloader.new()
	add_child_autofree(downloader)
	_served.clear()


func after_each() -> void:
	_cleanup()
	super()


func _cleanup() -> void:
	ModPackage.remove_directory_recursive(ROOT)


# ── the store: the player's feed list ────────────────────────────────────

func test_a_fresh_store_seeds_the_official_repository_and_writes_itself() -> void:
	assert_eq(store.repository_count(), 1, "one feed on the list before anything is added")
	var record: Dictionary = store.get_repositories()[0]
	assert_eq(str(record.get("url", "")), ModRepositoryStore.OFFICIAL_REPOSITORY_URL,
		"the game's own GitHub feed")
	assert_true(bool(record.get("official", false)))
	assert_eq(str(record.get("name", "")), ModRepositoryStore.OFFICIAL_REPOSITORY_NAME)
	assert_true(FileAccess.file_exists(store.store_path()),
		"the seeded list is written so the player's removals are honoured later")


func test_adding_a_feed_validates_deduplicates_and_persists() -> void:
	var added: Dictionary = store.add_repository("  https://example.com/my-mods.json  ")
	assert_true(bool(added.get("ok", false)), "a plain https address is accepted")
	assert_eq(str(added.get("url", "")), "https://example.com/my-mods.json", "the address is trimmed")
	assert_eq(store.repository_count(), 2)

	var again: Dictionary = store.add_repository("https://example.com/my-mods.json")
	assert_false(bool(again.get("ok", false)), "the same feed twice is refused")
	assert_true(("; ".join(again.get("errors", []))).contains("already"))

	var relative: Dictionary = store.add_repository("my-mods.json")
	assert_false(bool(relative.get("ok", false)), "a relative address is not a feed")
	assert_true(("; ".join(relative.get("errors", []))).contains("http"))
	var ftp: Dictionary = store.add_repository("ftp://example.com/mods.json")
	assert_false(bool(ftp.get("ok", false)))
	var blank: Dictionary = store.add_repository("   ")
	assert_false(bool(blank.get("ok", false)))

	# What the list accepted survives a reload from disk.
	var reloaded := ModRepositoryStore.new(store.store_root)
	assert_eq(reloaded.repository_count(), 2)
	assert_true(reloaded.has_repository("https://example.com/my-mods.json"))


func test_the_official_repository_is_a_normal_entry_once_added() -> void:
	assert_true(store.official_repository_present())
	assert_true(store.is_official(ModRepositoryStore.OFFICIAL_REPOSITORY_URL))
	assert_false(store.is_official("https://example.com/other.json"))

	var removed: Dictionary = store.remove_repository(ModRepositoryStore.OFFICIAL_REPOSITORY_URL)
	assert_true(bool(removed.get("ok", false)), "the list is the player's: the official feed can go")
	assert_false(store.official_repository_present())
	assert_eq(store.repository_count(), 0)

	assert_true(store.restore_official_repository(), "restoring puts it back")
	assert_true(store.official_repository_present())
	assert_false(store.restore_official_repository(), "restoring twice changes nothing")


func test_removing_an_unknown_feed_says_so() -> void:
	var result: Dictionary = store.remove_repository("https://example.com/never-added.json")
	assert_false(bool(result.get("ok", false)))
	assert_false(("; ".join(result.get("errors", []))).is_empty())


func test_a_fetched_feed_name_is_remembered_for_offline_boots() -> void:
	assert_true(store.note_feed_name(ModRepositoryStore.OFFICIAL_REPOSITORY_URL, "  Renamed Feed  "),
		"a new name is kept")
	assert_eq(str(store.repository_for(ModRepositoryStore.OFFICIAL_REPOSITORY_URL).get("name", "")),
		"Renamed Feed")
	assert_false(store.note_feed_name(ModRepositoryStore.OFFICIAL_REPOSITORY_URL, ""),
		"an empty name changes nothing")
	assert_false(store.note_feed_name("https://example.com/not-on-the-list.json", "X"),
		"nor does a name for a feed that is not on the list")
	var reloaded := ModRepositoryStore.new(store.store_root)
	assert_eq(str(reloaded.repository_for(ModRepositoryStore.OFFICIAL_REPOSITORY_URL).get("name", "")),
		"Renamed Feed", "and the name survives a reload")


func test_a_stored_list_ignores_damaged_entries_but_keeps_the_rest() -> void:
	var raw := [
		{"url": "https://example.com/keep.json", "name": "Keep", "official": false},
		{"url": "not a url"},
		{"url": ""},
		"not even an object",
		{"url": "https://example.com/keep.json"},
	]
	var parsed: Array[Dictionary] = ModRepositoryStore.parse_repositories(raw)
	assert_eq(parsed.size(), 1, "one usable entry survives")
	assert_eq(str(parsed[0].get("url", "")), "https://example.com/keep.json")
	assert_eq(str(parsed[0].get("name", "")), "Keep")
	assert_eq(ModRepositoryStore.parse_repositories("nope").size(), 0,
		"a non-list is no repositories at all")

	# A store file holding only garbage reads as empty rather than seeding -
	# the player removed their feeds on purpose; the Official feed comes
	# back through Restore.
	var file := FileAccess.open(store.store_path(), FileAccess.WRITE)
	file.store_string("{\"version\": 1, \"repositories\": [\"junk\"]}")
	file.close()
	var damaged := ModRepositoryStore.new(store.store_root)
	assert_eq(damaged.repository_count(), 0)


# ── the feed format ──────────────────────────────────────────────────────

const GOOD_FEED := """{
	"format_version": 1,
	"name": "Backyard Mods",
	"description": "A hand-rolled feed.",
	"mods": [
		{
			"id": "tester.cool_mod",
			"name": "Cool Mod",
			"version": "1.2.0",
			"author": "tester",
			"description": "Does a thing.",
			"download_url": "https://example.com/mods/cool_mod-1.2.0.zip",
			"size_bytes": 2048,
			"api_version": 1
		}
	]
}"""


func test_a_well_formed_feed_parses_into_entries() -> void:
	var feed := ModRepositoryFeed.parse(GOOD_FEED, "https://example.com/my-mods.json")
	assert_true(feed.is_valid(), "; ".join(feed.errors))
	assert_eq(feed.name, "Backyard Mods")
	assert_eq(feed.description, "A hand-rolled feed.")
	assert_eq(feed.source_url, "https://example.com/my-mods.json")
	assert_eq(feed.entry_count(), 1)
	var entry := feed.entry_for("tester.cool_mod")
	assert_eq(str(entry.get("name", "")), "Cool Mod")
	assert_eq(str(entry.get("version", "")), "1.2.0")
	assert_eq(str(entry.get("author", "")), "tester")
	assert_eq(str(entry.get("download_url", "")), "https://example.com/mods/cool_mod-1.2.0.zip")
	assert_eq(int(entry.get("size_bytes", 0)), 2048)
	assert_eq(int(entry.get("api_version", 0)), 1)
	assert_true(feed.has_entry("tester.cool_mod"))
	assert_false(feed.has_entry("tester.absent"))


func test_a_feed_that_will_not_parse_comes_back_invalid_and_quiet() -> void:
	var broken := ModRepositoryFeed.parse("{ this is not json", "https://example.com/x.json")
	assert_false(broken.is_valid())
	assert_true(broken.errors[0].contains("not valid JSON"))
	assert_eq(broken.entry_count(), 0)

	var array := ModRepositoryFeed.parse("[1, 2, 3]")
	assert_false(array.is_valid())
	assert_true(array.errors[0].contains("JSON object"))


func test_a_feed_of_the_wrong_format_version_is_refused() -> void:
	var feed := ModRepositoryFeed.parse("{\"format_version\": 99, \"mods\": []}")
	assert_false(feed.is_valid())
	assert_true(feed.errors[0].contains("format_version"))


func test_a_feed_without_a_mods_list_is_refused() -> void:
	var missing := ModRepositoryFeed.parse("{\"format_version\": 1, \"name\": \"Empty\"}")
	assert_false(missing.is_valid())
	assert_true(missing.errors[0].contains("mods"))
	var wrong_type := ModRepositoryFeed.parse("{\"format_version\": 1, \"mods\": \"nope\"}")
	assert_false(wrong_type.is_valid())


func test_unusable_entries_are_dropped_and_explained() -> void:
	var text := """{
		"format_version": 1,
		"mods": [
			{"name": "No id", "download_url": "https://example.com/a.zip"},
			{"id": "tester.bad id!", "download_url": "https://example.com/b.zip"},
			{"id": "tester.no_url"},
			{"id": "tester.ftp", "download_url": "ftp://example.com/c.zip"},
			"just a string",
			{"id": "tester.good", "download_url": "https://example.com/good.zip"}
		]
	}"""
	var feed := ModRepositoryFeed.parse(text)
	assert_eq(feed.entry_count(), 1, "only the usable entry is listed")
	assert_eq(str(feed.entry_for("tester.good").get("download_url", "")), "https://example.com/good.zip")
	assert_eq(feed.entry_errors.size(), 5, "and every drop is explained")
	for line in feed.entry_errors:
		assert_false(line.is_empty())
	# A feed whose entries all dropped is still a valid feed: the document
	# parsed; it just offers nothing.
	assert_true(feed.is_valid())


func test_a_feed_without_a_name_is_still_listable() -> void:
	var feed := ModRepositoryFeed.parse("{\"format_version\": 1, \"mods\": []}")
	assert_true(feed.is_valid())
	assert_eq(feed.name, ModRepositoryFeed.FALLBACK_NAME)


func test_duplicate_ids_keep_the_first_listing() -> void:
	var text := """{
		"format_version": 1,
		"mods": [
			{"id": "tester.twice", "version": "1.0.0", "download_url": "https://example.com/one.zip"},
			{"id": "tester.twice", "version": "2.0.0", "download_url": "https://example.com/two.zip"}
		]
	}"""
	var feed := ModRepositoryFeed.parse(text)
	assert_eq(feed.entry_count(), 1)
	assert_eq(str(feed.entry_for("tester.twice").get("version", "")), "1.0.0")
	assert_eq(feed.entry_errors.size(), 1)


func test_feed_urls_must_be_plain_http_or_https() -> void:
	assert_true(ModRepositoryFeed.is_downloadable_url("https://example.com/a.zip"))
	assert_true(ModRepositoryFeed.is_downloadable_url("HTTP://example.com/a.zip"))
	assert_false(ModRepositoryFeed.is_downloadable_url("ftp://example.com/a.zip"))
	assert_false(ModRepositoryFeed.is_downloadable_url("file:///etc/passwd"))
	assert_false(ModRepositoryFeed.is_downloadable_url(""))
	assert_false(ModRepositoryFeed.is_downloadable_url("example.com/a.zip"))
	assert_true(ModRepositoryFeed.is_fetchable_url("https://example.com/feed.json"))
	assert_false(ModRepositoryFeed.is_fetchable_url("javascript:alert(1)"))


func test_entries_sort_by_name_for_display_then_by_id() -> void:
	assert_true(ModRepositoryFeed.entry_before(
		{"id": "b.two", "name": "Alpha"}, {"id": "a.one", "name": "Beta"}),
		"by the name a player reads")
	assert_true(ModRepositoryFeed.entry_before(
		{"id": "a.one", "name": "Alpha"}, {"id": "b.two", "name": "alpha"}),
		"case apart, the id decides")
	assert_true(ModRepositoryFeed.entry_before(
		{"id": "a.one", "name": "Same"}, {"id": "b.two", "name": "Same"}))


# ── the downloader, over a local fetcher ─────────────────────────────────

func _serve(url: String, on_done: Callable) -> void:
	var answer: Dictionary = _served.get(url, {
		"ok": false, "status": 0, "bytes": PackedByteArray(),
		"errors": ["No local answer for %s" % url],
	})
	on_done.call(answer.duplicate(true))


func _serve_file(url: String, path: String) -> void:
	_served[url] = {"ok": true, "status": 200,
		"bytes": FileAccess.get_file_as_bytes(path), "errors": [] as Array[String]}


func _serve_failure(url: String, message: String) -> void:
	_served[url] = {"ok": false, "status": 0, "bytes": PackedByteArray(),
		"errors": [message] as Array[String]}


func _test_mod_zip() -> String:
	var folder := ROOT.path_join("src/tester.downloaded")
	DirAccess.make_dir_recursive_absolute(folder)
	var file := FileAccess.open(folder.path_join("mod.json"), FileAccess.WRITE)
	file.store_string("""{
	"format_version": 1, "id": "tester.downloaded", "name": "Downloaded",
	"version": "1.0.0", "api_version": 1, "description": "test"
}""")
	file.close()
	var zip_path := ROOT.path_join("tester.downloaded.zip")
	assert_true(bool(ModPackage.pack_folder(folder, zip_path).get("ok", false)))
	return zip_path


func test_fetch_feed_parses_the_answer() -> void:
	_serve_file("https://example.com/my-mods.json", _write_feed(GOOD_FEED))
	downloader.fetch_override = _serve
	var results: Array = []
	downloader.fetch_feed(
"https://example.com/my-mods.json",
		func(r: Dictionary) -> void: results.append(r))
	var result: Dictionary = results[0] if not results.is_empty() else {}
	assert_true(bool(result.get("ok", false)))
	var feed: ModRepositoryFeed = result.get("feed", null)
	assert_not_null(feed)
	assert_eq(feed.entry_count(), 1)
	assert_eq(feed.source_url, "https://example.com/my-mods.json")


func _write_feed(text: String) -> String:
	DirAccess.make_dir_recursive_absolute(ROOT)
	var path := ROOT.path_join("feed.json")
	var file := FileAccess.open(path, FileAccess.WRITE)
	file.store_string(text)
	file.close()
	return path


func test_fetch_feed_reports_feed_errors_as_its_own() -> void:
	_serve_file("https://example.com/broken.json", _write_feed("{ nope"))
	downloader.fetch_override = _serve
	var results: Array = []
	downloader.fetch_feed(
"https://example.com/broken.json",
		func(r: Dictionary) -> void: results.append(r))
	var result: Dictionary = results[0] if not results.is_empty() else {}
	assert_false(bool(result.get("ok", false)))
	assert_true(("; ".join(result.get("errors", []))).contains("JSON"))


func test_fetch_feed_carries_a_failed_request_through() -> void:
	_serve_failure("https://down.example.com/feed.json", "Could not connect to the server - check your connection.")
	downloader.fetch_override = _serve
	var results: Array = []
	downloader.fetch_feed(
"https://down.example.com/feed.json",
		func(r: Dictionary) -> void: results.append(r))
	var result: Dictionary = results[0] if not results.is_empty() else {}
	assert_false(bool(result.get("ok", false)))
	assert_null(result.get("feed", null))
	assert_eq(result.get("errors", []).size(), 1)


func test_download_and_install_lands_an_ordinary_library_mod() -> void:
	var zip_path := _test_mod_zip()
	var url := "https://example.com/mods/tester.downloaded.zip"
	_serve_file(url, zip_path)
	downloader.fetch_override = _serve
	downloader.install_root = ROOT.path_join("installed")
	downloader.download_root = ROOT.path_join("downloads")
	var results: Array = []
	downloader.download_and_install(
		{"id": "tester.downloaded", "name": "Downloaded", "version": "1.0.0",
			"download_url": url},
		func(r: Dictionary) -> void: results.append(r))
	var result: Dictionary = results[0] if not results.is_empty() else {}
	assert_true(bool(result.get("ok", false)), "; ".join(result.get("errors", [])))
	assert_eq(str(result.get("mod_id", "")), "tester.downloaded")
	var installed_root := str(result.get("directory", ""))
	assert_true(FileAccess.file_exists(installed_root.path_join("mod.json")),
		"the mod unpacks where any installed zip would")
	# The scratch copy never lingers.
	assert_false(FileAccess.file_exists(downloader.download_root.path_join("mod-tester.downloaded.zip")),
		"the downloaded zip is scratch space, cleaned up after the install")


func test_download_and_install_refuses_an_entry_without_a_usable_url() -> void:
	downloader.fetch_override = _serve
	var results: Array = []
	downloader.download_and_install(
		{"id": "tester.nourl"},
		func(r: Dictionary) -> void: results.append(r))
	var result: Dictionary = results[0] if not results.is_empty() else {}
	assert_false(bool(result.get("ok", false)))
	assert_true(("; ".join(result.get("errors", []))).contains("download_url"))


func test_download_and_install_refuses_an_entry_that_claims_an_impossible_size() -> void:
	downloader.fetch_override = _serve
	var results: Array = []
	downloader.download_and_install(
		{"id": "tester.huge", "download_url": "https://example.com/huge.zip",
			"size_bytes": ModPackage.MAX_ZIP_BYTES + 1},
		func(r: Dictionary) -> void: results.append(r))
	var result: Dictionary = results[0] if not results.is_empty() else {}
	assert_false(bool(result.get("ok", false)))
	assert_true(("; ".join(result.get("errors", []))).contains("MB"))
	assert_true(ModRepositoryDownloader.entry_size_is_impossible(
		{"size_bytes": ModPackage.MAX_ZIP_BYTES + 1}))
	assert_false(ModRepositoryDownloader.entry_size_is_impossible(
		{"size_bytes": ModPackage.MAX_ZIP_BYTES}))
	assert_false(ModRepositoryDownloader.entry_size_is_impossible({"size_bytes": 0}),
		"no size claimed, no size refused")


func test_a_download_that_is_not_a_mod_zip_reports_why() -> void:
	var url := "https://example.com/not-a-mod.zip"
	_served[url] = {"ok": true, "status": 200,
		"bytes": PackedByteArray([1, 2, 3, 4]), "errors": [] as Array[String]}
	downloader.fetch_override = _serve
	downloader.install_root = ROOT.path_join("installed")
	downloader.download_root = ROOT.path_join("downloads")
	var results: Array = []
	downloader.download_and_install(
		{"id": "tester.junk", "download_url": url},
		func(r: Dictionary) -> void: results.append(r))
	var result: Dictionary = results[0] if not results.is_empty() else {}
	assert_false(bool(result.get("ok", false)))
	var explanation := "; ".join(result.get("errors", []))
	assert_true(explanation.contains("zip"), "the package reader's explanation surfaces: " + explanation)


func test_a_failed_download_reports_the_fetch_error() -> void:
	var url := "https://down.example.com/cool.zip"
	_serve_failure(url, "The server did not answer in time.")
	downloader.fetch_override = _serve
	var results: Array = []
	downloader.download_and_install(
		{"id": "tester.cool", "download_url": url},
		func(r: Dictionary) -> void: results.append(r))
	var result: Dictionary = results[0] if not results.is_empty() else {}
	assert_false(bool(result.get("ok", false)))
	assert_true(("; ".join(result.get("errors", []))).contains("in time"))


func test_progress_questions_answer_honestly_without_a_live_request() -> void:
	assert_false(downloader.is_fetching("https://example.com/anything"))
	assert_lt(downloader.progress_of("https://example.com/anything"), 0.0,
		"no request, no progress")


func test_network_errors_read_like_advice_not_enums() -> void:
	assert_true(ModRepositoryDownloader._network_error(HTTPRequest.RESULT_CANT_RESOLVE)
		.contains("resolved"))
	assert_true(ModRepositoryDownloader._network_error(HTTPRequest.RESULT_TIMEOUT)
		.contains("in time"))
	assert_true(ModRepositoryDownloader._network_error(HTTPRequest.RESULT_TLS_HANDSHAKE_ERROR)
		.contains("certificate"))
	assert_true(ModRepositoryDownloader._network_error(999).contains("999"))
