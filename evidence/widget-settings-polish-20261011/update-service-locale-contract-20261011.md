# App updater locale and copy contract — 2026-10-11

Baseline inventory of `lib/services/app_update_service.dart`, `lib/core/app_update_policy.dart`, update UI consumers, and existing tests before lazy copy-model integration. `lib/core/app_update_ui_copy.dart` now defines that localized copy model. This subtask changed only the copy model and this report; service/UI/test integration is tracked separately. No analyzer or test command was run.

## Added lazy copy model

`AppUpdateNotice` and `AppUpdateNoticeKind` in `lib/core/app_update_ui_copy.dart` represent app-owned updater copy until render time. `render(locale:)` uses the supplied `AppLocale` or the current `I18n` locale. `AppUpdateNotice.literal(text)` returns externally authored release notes or server policy reasons unchanged, preserving whitespace, Markdown, and URLs. Error-bearing notices pass their cause through `userVisibleApiError` with the selected locale.

Generated release-note copy says that notes were not provided, optionally naming the target version; it does not claim fixes or improvements absent from the supplied notes. The check-failure notice retains the generic service-unavailable fallback used by existing API error handling. Keep generated fallback copy out of `_latestNotes`; resolve it only when displaying a missing-notes state.

## Current data and display paths

`AppUpdateService.checkNow()` checks `/api/mobile/apps/duoyi/update` first, then `/api/config` when the mobile endpoint did not load policy. A valid mobile response skips `/api/config`; missing display fields can still be filled from the latest GitHub release. A 404 or explicitly recognized backend contract mismatch can enter compatibility fallback. Other backend errors throw. When no server policy loads, `checkNow()` uses GitHub as the release source. Startup calls `checkServerPolicyNow()` from `main.dart:2826–2833`; it checks mobile then config and does not fetch GitHub notes unless policy loaded and an update needs a missing download URL (`main.dart:5529–5530` shows the blocking gate when `mustUpdate` is true).

| Source | Fields consumed | Current handling |
|---|---|---|
| Mobile update API | `available`, `latest_version_name`, `latest_version_code`, `minimum_supported_version`, `minimum_supported_version_code`, `download_url`, `release_notes`, `force_update`, `force_update_required`, `force_app_update_enabled`, `force_update_blocked_reason` | Notes and blocked reason pass through `_stringValue`, which calls `toString().trim()`. A blank/no-update response returns before assigning the blocked reason (`app_update_service.dart:350–398`). |
| `/api/config` (nested `app_update` or root object) | `latest_version`, `latest_version_code`, `minimum_supported_version`, `minimum_supported_version_code`, `update_download_url`, `update_notes`, `force_update_required`, `force_app_update_enabled` | Notes are trimmed; blocked reason is always cleared because this contract does not read one (`:256–307`). |
| GitHub latest release | `tag_name`, `body`, `assets` | `body` is trimmed and may fill missing server notes. If GitHub reports a newer target version than the loaded server target, its notes can replace already supplied notes (`:652–748`). |
| Web `version.json` | `version`, `build_number` | Clears notes and force-update state; `mustUpdate` is always false on web (`:428–468`, `:86–97`). |

The selected notes are held only in `_latestNotes`; `latestNotes` exposes that raw-ish field, but both `MineScreen` and `ForceUpdateGate` render `latestNotesForDisplay` (`app_update_service.dart:35–68`; `mine_screen.dart:694`; `force_update_gate.dart:32`). That getter applies `formatUpdateNotesForDisplay`, which trims, normalizes CRLF, removes HTML comments and Markdown link destinations, removes selected heading/changelog lines, deduplicates and caps at eight summary lines, then prepends the Chinese label `本次更新摘要：` (`app_update_policy.dart:64–105`). Thus current rendering does **not** preserve supplied release notes literally.

Generated note fallback is assigned when server policy has no notes by `checkNow()` (`app_update_service.dart:152–154`), `checkServerPolicyNow()` (`:200–205`), or cached installer restoration (`:827–842`). `_fallbackUpdateNotes` generates a Chinese sentence, with or without a version (`:1062–1068`). If formatted notes are still empty while a latest version exists, `latestNotesForDisplay` returns `此版本没有填写更新说明。` (`:63–68`). Neither notes nor errors nor blocked reasons are written to preferences. Preferences persist only downloaded installer path, version, version code, URL, and asset name (`:13–19`, `:887–918`).

`force_update_blocked_reason` is free-form display copy, not an enforcement input. It is held in `_forceUpdateBlockedReason`, cleared on config reset/web and never persisted. Mine shows it verbatim between localized prefix/suffix strings when an update is required/available but there is no URL or cached installer (`mine_screen.dart:776–788`). The startup `ForceUpdateGate` does not render that field; it shows a generic missing-installer banner (`force_update_gate.dart:170–180`).

## Enforcement and copy are separate

Keep the enforcement state machine and copy model independent. `forceUpdateRequired`, `hasUpdate`, and `mustUpdate` are the machine state. On the mobile endpoint, force is `force_update == true` or an enabled policy combined with `available || belowMinimum` (`app_update_service.dart:371–398`). `/api/config` treats either `force_update_required` or `force_app_update_enabled` as the policy flag (`:287–306`). `shouldForceAppUpdate` first requires the policy flag, compares newer build codes when available, then version and minimum-supported-version values (`app_update_policy.dart:19–61`). It does not consult any message or blocked reason. No UI should infer required-update enforcement by parsing a localized string or `force_update_blocked_reason`.

Contract to preserve during integration:

- Use `AppUpdateNoticeKind` for app-owned UI states, with status codes and diagnostics held as structured fields where needed; do not construct UI copy by concatenating exception text.
- Keep supplied release notes as their original string and render them with `AppUpdateNotice.literal`; retain whitespace, line breaks, Markdown, and URLs, using `trim().isEmpty` only to detect absence. Resolve the `generatedReleaseNotes` notice only when notes are missing, and keep that generated copy out of `_latestNotes`. Avoid replacing supplied notes with a GitHub body for another target version.
- Keep the backend `force_update_blocked_reason` as a literal server-authored string. Validate its type as a string, use whitespace only to decide whether it is absent, and retain the original value for display. Localize only the surrounding app-owned label/prefix/suffix. Do not convert the text into a reason code or use it to decide whether the update is mandatory.
- Expose a structured error/reason from the service and localize it in the UI at render time. Separate safe user copy from diagnostic detail. Do not expose `$e`, raw exception text, HTTP internals, or server compatibility diagnostics in the user-facing field.

For missing release notes, prefer an honest localized `releaseNotesUnavailable` fallback over claims that the release contains fixes that were not supplied. If product needs an explanatory summary, render it from a typed fallback descriptor rather than storing a prelocalized string in `_latestNotes`.

## Error storage and currently emitted service copy

`error` is an in-memory `String?`. Both `checkNow()` and `checkServerPolicyNow()` clear it at start, assign `userVisibleApiError(e)` on failure, and clear it again if a downloaded installer is available (`app_update_service.dart:99–163`, `:166–215`). `_checkWebManifest()` also assigns `userVisibleApiError(e)` (`:428–468`). The private `_BackendUpdateCheckException` is an `Exception`, not an `ApiException`; `userVisibleApiError` therefore returns its locale-specific generic backend fallback instead of its `message` (`api_client.dart:527–565`, `app_update_service.dart:1071–1081`). Its detailed Chinese HTTP/contract diagnostics are not the normal displayed error; compatibility details are logged at debug level.

Directly assigned service strings that can be shown to users today:

| Copy | Assignment and rendering |
|---|---|
| `此版本没有填写更新说明。` | `latestNotesForDisplay` when a version exists but formatted notes are empty (`app_update_service.dart:63–68`). |
| `本次更新会修复已知问题并优化稳定性。` / `版本 $target 包含已知问题修复、稳定性优化和体验改进。` | `_fallbackUpdateNotes` when server policy/installer restoration needs a local note (`:841`, `:1062–1068`); currently passed through the Chinese summary formatter. |
| `本次更新摘要：` | `formatUpdateNotesForDisplay` (`app_update_policy.dart:49–68`); prepended even when the supplied release-note body is English. |
| `尚未发布 Release` / `检查更新失败: ${resp.statusCode}` | `_mergeGitHubLatestRelease` on GitHub 404 / non-200 when not retaining server policy (`app_update_service.dart:666–677`). |
| `需要允许多仪安装未知应用；授权后返回这里再次点击安装` | `_tryInstallDownloadedInstaller` and `downloadAndInstallLatest` when Android install permission is absent (`:928–948`, `:992–998`). |
| `当前平台不支持应用内 APK 更新` / `没有可下载的 APK` / `更新失败: $e` | `downloadAndInstallLatest` unsupported-platform, absent-URL, and download/install exception branches (`:951–1007`). `$e` may expose technical details; the force gate renders `updater.error` directly. |

Updater check failures also inherit `userVisibleApiError` copy: Chinese `服务暂不可用，请稍后重试或联系管理员`, `无法连接服务器，请检查网络后重试`, or `连接超时，请稍后重试` (with English equivalents in `api_client.dart:515–565`). In the updater, custom backend exceptions normally take the generic fallback path. `_mergeGitHubLatestRelease` status strings and installer strings bypass that helper.

Other Chinese strings in `app_update_service.dart` construct internal backend contract diagnostics (`:230–403`, `:449–456`, `:549–593`), including missing/outdated `api_contract_version`, missing/mismatched `required_routes_hash`, and “请部署当前 backend/main.py 后再重试。” They are thrown in `_BackendUpdateCheckException` and are sanitized to the generic error in current catch paths; do not treat them as established user-facing copy.

`ForceUpdateGate` separately owns hardcoded Chinese UI copy rather than service copy (`force_update_gate.dart:88–225`): `需要更新后才能继续使用`; `管理员已开启强制更新策略。更新完成前，应用功能会暂时锁定。`; `当前版本`; `最新版本`; `未配置`; `最低支持版本`; `安装包`; `更新内容`; `安装包暂不可用`; `管理员未配置下载地址，或发布通道还没有提供可安装的新版本。请等待发布包同步完成。`; `当前平台不支持应用内安装`; `请在 Android 手机上安装更新包；桌面或 Web 端仅展示更新说明。`; `正在下载更新包`; `正在下载 …%`; `正在打开安装器`; `安装已下载包`; `下载并安装`.

## Locale-switch behavior

`I18n.setLocale` updates `I18n.current` and notifies `localeListenable` (`i18n.dart:2376–2400`). The Mine update dialog is wrapped in a `ValueListenableBuilder` for that notifier and uses bilingual `mine.update.*` keys (`mine_screen.dart:622–631`; `i18n.dart:1107–1133`, `:2317–2347`), including the blocked-reason prefix/suffix. Its app-owned labels re-resolve on a locale switch; supplied notes remain in their supplied language. `AccountUiCopy.formatError` is called during rebuild and can translate recognized error categories using the current locale, but an unrecognized updater `String` falls through as-is (`account_ui_copy.dart:59–278`).

`AppUpdateService` does not listen to locale changes. Its generated notes are fixed Chinese strings, and `_error` is stored as a localized string at assignment time. `ForceUpdateGate` has no I18n import/listener, uses hardcoded Chinese, and displays `updater.error` directly; its copy remains Chinese after a locale switch. No updater-specific locale-switch test was found in the focused test files.

## Existing relevant tests

`test/services/app_update_service_test.dart` covers the service contract and policy:

- Notes/fallbacks: `release notes display hides GitHub generated full changelog link` (line 14); `backend mobile update fills missing release notes from GitHub` (240); `server policy startup check avoids GitHub and uses fallback notes` (352).
- Enforcement: `minimum supported version only locks app when force update is enabled` (30); `server force update policy blocks current app when version is raised` (55); `same version with newer build code still surfaces update` (316); `backend mobile minimum supported version can force update` (419); `mobile force_update response is honored directly` (560); `backend force update switch also locks when backend reports blocked url` (702); `server config force update fallback blocks even without manual url` (726).
- Endpoint/error/fallback paths: `client uses backend mobile update before GitHub fallback` (90); `backend update errors do not silently fall back to GitHub` (124); `mobile update 404 with stale backend contract still falls back to GitHub` (142); `server config with outdated contract still falls back to GitHub` (178); `server config with route hash mismatch still falls back to GitHub` (207); `mobile update 200 with route hash mismatch still falls back to GitHub` (664); `startup policy check hides stale backend compatibility prompt` (387).
- Version, installer, and blocked reason: `backend update request sends real build code when provided` (277); `stale backend update versions are displayed as current version` (451); `backend stale apk url is replaced by release channel apk` (499); `check update restores downloaded installer without network` (597); `stale downloaded installer url is not reused offline` (632); `backend update checks normalize trailing slash base urls` (748); `backend update download urls are resolved and blocked reasons surface` (768). The last is source-assertion coverage; it does not assert literal whitespace preservation or that the force gate displays the server reason.

Other focused files:

- `test/services/admin_force_update_settings_test.dart`: `force update defaults track the repository version` (line 7) and `admin settings expose force update policy through config` (38); static contract assertions include the policy booleans and the blocking gate.
- `test/widgets/force_update_gate_screenshot_test.dart`: `强制更新页桌面尺寸全屏覆盖` (16), `强制更新页手机尺寸全屏覆盖` (20), and `强制更新页 320px 下长安装包名可换行展示` (24); these assert current Chinese gate copy.
- `test/widgets/notification_update_narrow_layout_static_test.dart`: `检查更新弹窗安装包名使用可换行信息块` (39) and `强制更新信息行长值支持 320px 换行展示` (50).
- `test/screens/profile_screen_test.dart`: `mine narrow header keeps long admin metadata and update badge visible` (459); this covers the badge, not update-note/error localization.

No focused test currently checks a locale switch while the update dialog/gate is open, preservation of release-note whitespace/Markdown/link text, generated-note localization, structured error reasons, or exact preservation of `force_update_blocked_reason`.
