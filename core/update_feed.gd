extends Node
## Explicit, bounded release checks. Never downloads or installs APKs itself.
signal state_changed
const REPOSITORY = "Magral/Microgen"
const API_URL = "https://api.github.com/repos/" + REPOSITORY + "/releases/latest"
const RELEASE_BASE = "https://github.com/" + REPOSITORY + "/releases/"
const MANIFEST_NAME = "microgen-update.json"
const MAX_APK_BYTES = 536870912
var installed_version: String = str(ProjectSettings.get_setting("application/config/version", "1.0.0"))
var installed_version_code: int = int(ProjectSettings.get_setting("application/config/version_code", 0))
var state: Dictionary = {"status":"idle", "newest":"", "download_url":"", "release_url":"", "error":""}
var _request: HTTPRequest
var _phase = ""
var _release: Dictionary = {}

static func semver(value: Variant) -> Array:
	if not value is String: return []
	var rx = RegEx.new()
	rx.compile("^v?(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})$")
	var found = rx.search(value)
	if found == null: return []
	return [int(found.get_string(1)), int(found.get_string(2)), int(found.get_string(3))]

static func compare_versions(a: String, b: String) -> int:
	var left = semver(a)
	var right = semver(b)
	if left.is_empty() or right.is_empty(): return 0
	for i in range(3):
		if left[i] != right[i]: return 1 if left[i] > right[i] else -1
	return 0

static func valid_asset_url(url: Variant, tag: String, extension: String) -> bool:
	if not url is String or semver(tag).is_empty(): return false
	var prefix = RELEASE_BASE + "download/" + tag + "/"
	if not url.begins_with(prefix): return false
	var file = url.trim_prefix(prefix)
	var rx = RegEx.new()
	rx.compile("^[A-Za-z0-9][A-Za-z0-9._-]{0,150}\\." + extension + "$")
	return rx.search(file) != null and not ".." in file

static func parse_release(data: Variant) -> Dictionary:
	if not data is Dictionary: return {"error":"Некорректный ответ GitHub."}
	if not data.get("draft") is bool or not data.get("prerelease") is bool or data.draft or data.prerelease:
		return {"error":"Тестовые и черновые выпуски не используются."}
	var tag = data.get("tag_name", "")
	if semver(tag).is_empty(): return {"error":"Некорректный номер выпуска."}
	var page = RELEASE_BASE + "tag/" + tag
	if data.get("html_url") != page: return {"error":"Выпуск из другого репозитория."}
	var assets = data.get("assets")
	if not assets is Array: return {"error":"Нет списка файлов выпуска."}
	var manifest_url = ""
	var apk_urls: Array = []
	for asset in assets:
		if not asset is Dictionary: continue
		var url = asset.get("browser_download_url", "")
		if asset.get("name") == MANIFEST_NAME and url == RELEASE_BASE + "download/" + tag + "/" + MANIFEST_NAME:
			manifest_url = url
		if valid_asset_url(url, tag, "apk"): apk_urls.append(url)
	return {"tag":tag, "release_url":page, "manifest_url":manifest_url, "apk_urls":apk_urls}

static func parse_manifest(data: Variant, release: Dictionary, local_version: String, local_code: int) -> Dictionary:
	if not data is Dictionary: return {"error":"Некорректный манифест обновления."}
	var version = data.get("version", "")
	var code = data.get("version_code", -1)
	if semver(version).is_empty() or semver(version) != semver(release.get("tag", "")):
		return {"error":"Версия манифеста не совпадает с выпуском."}
	if not (code is int or code is float) or not is_finite(float(code)) or float(code) != floor(float(code)) or code < 1 or code > 2100000000:
		return {"error":"Некорректный Android version_code."}
	var url = data.get("apk_url", "")
	if not valid_asset_url(url, release.get("tag", ""), "apk") or not url in release.get("apk_urls", []):
		return {"error":"APK не принадлежит проверенному выпуску."}
	var size = data.get("size_bytes", 0)
	if not (size is int or size is float) or not is_finite(float(size)) or float(size) != floor(float(size)) or size <= 0 or size > MAX_APK_BYTES:
		return {"error":"Некорректный размер APK."}
	var digest = data.get("sha256", "")
	var rx = RegEx.new()
	rx.compile("^[a-fA-F0-9]{64}$")
	if not digest is String or rx.search(digest) == null: return {"error":"Нет контрольной суммы APK."}
	if semver(local_version).is_empty(): return {"error":"Неизвестна установленная версия."}
	var newer = compare_versions(version, local_version) > 0 and int(code) > local_code
	return {"status":"available" if newer else "current", "newest":version, "version_code":int(code), "download_url":url if newer else "", "release_url":release.release_url, "sha256":digest.to_lower(), "size_bytes":int(size), "error":""}

func check_updates():
	cancel()
	_release = {}
	state = {"status":"checking", "newest":"", "download_url":"", "release_url":"", "error":""}
	state_changed.emit()
	_start_request(API_URL, "release", 1048576)

func _start_request(url: String, phase: String, limit: int):
	_phase = phase
	_request = HTTPRequest.new()
	_request.timeout = 15.0
	_request.body_size_limit = limit
	_request.max_redirects = 5
	add_child(_request)
	_request.request_completed.connect(_completed)
	var error = _request.request(url, PackedStringArray(["Accept: application/json", "User-Agent: Microgen-update-check"]))
	if error != OK: _fail("Не удалось начать проверку. Попробуйте ещё раз.")

func _dispose_request():
	if is_instance_valid(_request):
		_request.cancel_request()
		_request.queue_free()
	_request = null

func cancel():
	_dispose_request()
	_phase = ""
	if state.get("status") == "checking":
		state.status = "idle"
		state_changed.emit()

func _completed(result: int, response_code: int, _headers: PackedStringArray, body: PackedByteArray):
	var phase = _phase
	_dispose_request()
	if result != HTTPRequest.RESULT_SUCCESS or response_code != 200:
		_fail("GitHub недоступен (HTTP %d). Игра работает без сети. Повторите проверку позже." % response_code)
		return
	var json = JSON.new()
	if json.parse(body.get_string_from_utf8()) != OK:
		_fail("Некорректный JSON от сервера. Попробуйте позже.")
		return
	var data = json.data
	if phase == "release":
		_release = parse_release(data)
		if _release.has("error"):
			_fail(_release.error)
			return
		state.release_url = _release.release_url
		if _release.manifest_url.is_empty():
			_fail("У выпуска нет манифеста обновления. Файлы можно посмотреть на GitHub.")
			return
		_start_request(_release.manifest_url, "manifest", 65536)
	elif phase == "manifest":
		var parsed = parse_manifest(data, _release, installed_version, installed_version_code)
		if parsed.has("error") and not parsed.error.is_empty():
			_fail(parsed.error)
			return
		state = parsed
		state_changed.emit()

func _fail(message: String):
	_dispose_request()
	_phase = ""
	state.status = "error"
	state.error = message
	state.download_url = ""
	state_changed.emit()

func open_download() -> Error:
	var url = state.get("download_url", "")
	if state.get("status") != "available" or not valid_asset_url(url, _release.get("tag", ""), "apk"): return ERR_INVALID_PARAMETER
	var result = OS.shell_open(url)
	if result != OK: _fail("Не удалось открыть браузер. Откройте выпуск на GitHub.")
	return result

func open_release() -> Error:
	var page = state.get("release_url", "")
	if page != RELEASE_BASE + "tag/" + _release.get("tag", "") or semver(_release.get("tag", "")).is_empty(): return ERR_INVALID_PARAMETER
	var result = OS.shell_open(page)
	if result != OK: _fail("Не удалось открыть GitHub в браузере.")
	return result
