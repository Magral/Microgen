extends SceneTree
const Feed = preload("res://core/update_feed.gd")
const View = preload("res://ui/update_view.gd")
class OfflineFeed extends "res://core/update_feed.gd":
	var requests: Array = []
	func _start_request(url: String, phase: String, limit: int):
		_phase = phase
		requests.append([url, phase, limit])
var failures = 0
func check(ok: bool, message: String):
	if not ok:
		failures += 1
		push_error(message)
func _initialize(): call_deferred("run")
func run():
	var tag = "v1.10.2"
	var apk = Feed.RELEASE_BASE + "download/" + tag + "/Microgen-1.10.2.apk"
	var release = {"tag_name":tag, "html_url":Feed.RELEASE_BASE + "tag/" + tag, "draft":false, "prerelease":false, "assets":[{"name":"microgen-update.json", "browser_download_url":Feed.RELEASE_BASE + "download/" + tag + "/microgen-update.json"}, {"name":"Microgen-1.10.2.apk", "browser_download_url":apk}]}
	var parsed = Feed.parse_release(release)
	check(not parsed.has("error"), "stable release parses")
	check(Feed.compare_versions("1.10.2", "1.9.9") == 1, "versions compare numerically")
	check(Feed.compare_versions("v2.0.0", "1.99.99") == 1, "major takes precedence")
	check(Feed.compare_versions("1.0.0", "v1.0.0") == 0, "v prefix normalized")
	for version in ["1.0", "1.0.0-beta.1", "1.0.0+meta", "01.0.0", "1.-2.0", "1.0.0/path", "999999999999999.0.0", 100, null]:
		check(Feed.semver(version).is_empty(), "malformed/prerelease version rejected: %s" % str(version))
	for key in ["draft", "prerelease"]:
		var bad = release.duplicate(true)
		bad[key] = true
		check(Feed.parse_release(bad).has("error"), "reject " + key)
	var missing_assets = release.duplicate(true)
	missing_assets.assets = []
	var missing = Feed.parse_release(missing_assets)
	check(missing.get("manifest_url") == "" and missing.get("apk_urls") == [], "missing assets produce no APK URL")
	var wrong_repo = release.duplicate(true)
	wrong_repo.html_url = "https://github.com/other/Microgen/releases/tag/" + tag
	check(Feed.parse_release(wrong_repo).has("error"), "reject wrong repo release")
	for value in [null, [], "json", {"draft":false}]:
		check(Feed.parse_release(value).has("error"), "reject malformed release")
	for url in [apk.replace("github.com", "github.com.evil.com"), apk.replace("Magral", "other"), apk + "?redirect=evil", apk + "#fragment", apk.replace("https://", "http://"), apk.replace("Microgen-1.10.2.apk", "../evil.apk"), apk.replace("Microgen-1.10.2.apk", "%2E%2E.apk"), "file:///tmp/game.apk"]:
		check(not Feed.valid_asset_url(url, tag, "apk"), "reject untrusted URL " + url)
	var manifest = {"version":"1.10.2", "version_code":1102, "apk_url":apk, "size_bytes":1024, "sha256":"a".repeat(64)}
	var result = Feed.parse_manifest(manifest, parsed, "1.9.9", 1099)
	check(result.get("status") == "available", "newer version and code available")
	check(Feed.parse_manifest(manifest, parsed, "1.10.2", 1102).get("status") == "current", "same release not an update")
	check(Feed.parse_manifest(manifest, parsed, "2.0.0", 2000).get("status") == "current", "never offer downgrade")
	check(Feed.parse_manifest(manifest, parsed, "1.9.9", 1200).get("status") == "current", "Android code must increase")
	for patch in [{"version":"1.10.3"}, {"version_code":"1102"}, {"version_code":1.5}, {"version_code":0}, {"size_bytes":0}, {"size_bytes":536870913}, {"size_bytes":"1024"}, {"sha256":"bad"}, {"apk_url":apk.replace("Magral", "other")}, {"apk_url":apk.replace("Microgen-1.10.2.apk", "not-listed.apk")}]:
		var bad = manifest.duplicate(true)
		bad.merge(patch, true)
		check(Feed.parse_manifest(bad, parsed, "1.0.0", 100).has("error"), "reject malformed manifest " + str(patch))
	var service = OfflineFeed.new()
	root.add_child(service)
	check(service.requests.is_empty(), "creating service makes no network request")
	service.installed_version = "1.0.0"
	service.installed_version_code = 100
	service.check_updates()
	check(service.requests.size() == 1 and service.requests[0][0] == Feed.API_URL, "explicit check requests only fixed repository")
	service._completed(HTTPRequest.RESULT_TIMEOUT, 0, PackedStringArray(), PackedByteArray())
	check(service.state.status == "error" and service.state.download_url.is_empty(), "timeout recoverable without download")
	service.check_updates()
	check(service.requests.size() == 2, "retry after network failure")
	service._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(release).to_utf8_buffer())
	check(service.requests.size() == 3 and service.requests[-1][2] == 65536, "manifest uses bounded second request")
	service._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), JSON.stringify(manifest).to_utf8_buffer())
	check(service.state.status == "available", "successful mocked check offers browser APK")
	service.check_updates()
	service._completed(HTTPRequest.RESULT_SUCCESS, 429, PackedStringArray(), PackedByteArray())
	check(service.state.status == "error" and service.state.download_url.is_empty(), "rate limit never treated as update")
	service.check_updates()
	service._completed(HTTPRequest.RESULT_SUCCESS, 200, PackedStringArray(), "{bad json".to_utf8_buffer())
	check(service.state.status == "error", "malformed JSON recoverable")
	service.check_updates()
	service.cancel()
	check(service.state.status == "idle", "cancel clears checking state")
	check(service.open_download() == ERR_INVALID_PARAMETER, "cannot launch browser without validated available release")
	var hud = load("res://ui/hud.gd").new()
	var box = VBoxContainer.new()
	View.populate(hud, box, service, {})
	check(box.get_child_count() >= 4, "view builds status and explicit check without network")
	box.free()
	hud.free()
	service.queue_free()
	await process_frame
	print("UPDATES: %d failures" % failures)
	quit(0 if failures == 0 else 1)
