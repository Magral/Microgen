# Updates in Microgen 1.0

The main menu offers an explicit update check. Constructing the service, opening the menu, and playing never trigger network traffic. There is no background updater or automatic startup check. Checks use HTTPS to `https://api.github.com/repos/Magral/Microgen/releases/latest`, accept only a non-draft, non-prerelease numeric `vMAJOR.MINOR.PATCH` or `MAJOR.MINOR.PATCH` release, then fetch that release's `microgen-update.json` asset. Both semantic version and Android version code must increase before an update is offered.

Each request has a 15-second timeout, at most five redirects, and a response body limit (1 MiB release metadata, 64 KiB manifest). TLS certificate verification uses Godot defaults. Cancellation stops the request. Errors and API rate limits are shown with an explicit retry button; the game remains usable offline. No automatic retries or persisted network cache are used.

Only the fixed repository and release tag are accepted. APK URLs must be HTTPS GitHub release download URLs under `Magral/Microgen`, match the selected tag, have a safe `.apk` filename, and appear in that release's asset list. Arbitrary hosts, other repositories, HTTP, query strings, fragments, encoded paths, and traversal are rejected. This establishes release origin and metadata consistency; it is not a cryptographic signature or a guarantee against a compromised publisher account.

## Release manifest

Attach `microgen-update.json` alongside the APK in every stable GitHub release. Generate it from the final signed APK. Exact schema (replace example size and digest with measured values):

```json
{
  "version": "1.0.0",
  "version_code": 100,
  "apk_url": "https://github.com/Magral/Microgen/releases/download/v1.0.0/Microgen.apk",
  "size_bytes": 12345678,
  "sha256": "aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa"
}
```

`version` must match the release tag numerically. `version_code` must be an integer in 1–2100000000. `size_bytes` must be a positive integer at most 512 MiB. `sha256` must contain exactly 64 hexadecimal characters. Missing or malformed metadata fails closed. Older releases without the manifest can still be viewed through their validated GitHub release page.

The browser handles the APK download. The app does **not** download the APK itself and does **not** verify downloaded APK bytes against the manifest digest; the digest is validated as metadata only. Do not describe the browser handoff as an in-app checksum-verified download or installation.

## Android installation boundary

“Скачать APK через браузер” opens the validated asset URL with `OS.shell_open`. The user then opens the downloaded APK and approves Android's installation UI. Android may require the user to allow installation from that browser or file manager. The app does not silently install, launch a local `file://` APK intent, or request installer privileges.

This scope follows Godot 4.6's documented HTTPS browser handoff. A future direct installer would require a tested Android integration: an accessible `content://` URI with temporary read grants, appropriate package-install permissions/settings, and PackageInstaller result/user-action handling. Adding only a local download and `OS.shell_open(file_path)` would not establish a supported Android installation flow.

Keep the Android package identifier and signing key consistent with the installed app and increase `version/code` for every update. A mismatched signing certificate cannot normally update an existing installation. Do not tell users to uninstall to overcome signing errors: uninstalling can erase their local saves. Preserve the existing keystore securely.

Export requires `permissions/internet=true` for GitHub checks. It does not need `REQUEST_INSTALL_PACKAGES` or shared-storage permissions for the browser handoff. Set `application/config/version` and `application/config/version_code` in `project.godot` to the same version/code used by the Android export preset and release manifest.

## Integration and tests

`core/update_feed.gd` is a Node with `state_changed`, `check_updates()`, `cancel()`, `open_download()` and `open_release()`. State keys include `status` (`idle`, `checking`, `available`, `current`, `error`), `newest`, `download_url`, `release_url`, and `error`. Use it only from the menu. Cancel pending requests when leaving the update screen or starting gameplay. A failed browser launch becomes a visible service error.

`ui/update_view.gd.populate(hud, box, service, callbacks)` builds Russian menu content. Optional callbacks are `check`, `cancel`, `open_download`, `open_release`, `back`; service methods supply defaults except `back`. Redraw on `state_changed` only while the update screen is active.

Run `godot --headless --path . --script tests/test_updates.gd`. Tests mock transport without public network calls and cover numeric version ordering, malformed payloads, prerelease/draft exclusion, foreign repository/URL rejection, manifest/version code validation, missing assets, timeout, HTTP error, retry, cancellation, and successful two-stage checks. Browser download, installation confirmation, and preservation of saves across a signed upgrade still require real-device Android acceptance testing.

## Official references

- [Godot 4.6 OS.shell_open](https://docs.godotengine.org/en/4.6/classes/class_os.html#class-os-method-shell-open): HTTPS URLs open the default browser; this is resource handoff, not an installer API.
- [Godot 4.6 HTTPRequest](https://docs.godotengine.org/en/4.6/classes/class_httprequest.html): timeouts, body limits, redirects, cancellation, and Android INTERNET export requirement.
- [Android ACTION_INSTALL_PACKAGE](https://developer.android.com/reference/android/content/Intent#ACTION_INSTALL_PACKAGE): deprecated in API 29 in favor of PackageInstaller; requires a content URI and package-install permission for modern targets.
- [Android sharing files](https://developer.android.com/training/secure-file-sharing/share-file): FileProvider content URIs and temporary read permission grants.
- [Android app signing](https://developer.android.com/studio/publish/app-signing#considerations): updates depend on signing identity.
