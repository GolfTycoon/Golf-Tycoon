extends GameTest
## SteamWorkshopProvider without Steam: the provider's whole point is that
## builds without GodotSteam (like this one) fail soft - no singleton,
## no subscriptions, uploads refuse with the reason, nothing crashes.
## (scripts/modding/steam_workshop_provider.gd)


func test_without_godotsteam_there_is_no_workshop() -> void:
	var provider := SteamWorkshopProvider.new()
	assert_false(provider.is_available(), "no Steam singleton in this build")
	assert_eq(provider.get_subscribed_mod_roots(), [], "so nothing is subscribed")
	assert_eq(provider.app_id(), 0, "and no App ID is configured")
	assert_false(provider.open_workshop_page(), "nowhere to open")


func test_uploads_refuse_cleanly_without_steam() -> void:
	var provider := SteamWorkshopProvider.new()
	var manifest := ModManifest.from_dictionary({
		"format_version": 1, "id": "tester.uploader", "name": "Uploader",
		"version": "1.0.0", "api_version": 1,
	})
	var result: Dictionary = await provider.upload_mod(manifest, "/tmp/nothing")
	assert_false(bool(result.get("ok", true)))
	assert_true(str(result.get("message", "")).contains("not available"),
		"the player hears why, in words")
	assert_false(ModManager.steam_available(), "the manager agrees")
