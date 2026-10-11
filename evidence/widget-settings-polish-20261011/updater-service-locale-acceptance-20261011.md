# Updater service locale acceptance — 2026-10-11

## Accepted behavior

- App-owned update notices resolve their copy at render time for the selected locale. Typed errors retain safe API-specific messages where supported and use localized generic fallbacks for unexpected causes. Cached check failures can be rendered after a locale change without another network check; locale listeners are removed when the service is disposed.
- Supplied mobile API, config API, and GitHub release notes remain literal text, including their original whitespace and formatting. Missing notes use a lazy localized message that says notes were not provided and does not claim unsupplied fixes. Backend policy remains authoritative for the target version and force-update decision.
- GitHub notes and APK assets are considered only for the backend target version, and asset matching happens before ranking. A same-name newer build cannot be established from release tag or file-name metadata alone.
- Installer preflight failures are caught safely. Generic download/install failures use operation-neutral copy (`未能完成更新，请稍后重试。` / `Could not complete the update. Please try again.`); safe typed API and network details remain available.

## Verification

The accepted regression run covered three files and passed all 58 tests:

- `test/services/app_update_service_test.dart`
- `test/services/admin_force_update_settings_test.dart`
- `test/widgets/notification_update_narrow_layout_static_test.dart`

The updater tests include both-locale notice rendering and error sanitization, literal notes from each supported source, lazy missing-note copy, cached error re-rendering, backend target-version matching, and APK asset filtering before ranking.

Final focused analysis exited 0 with **No issues found** across 3 files (14.5 seconds). An earlier analyzer run reported two test brace infos; the test conditionals were braced and the final analyzer run supersedes that output. No updater source changed after the 58-test run.

Logs: `.dart_tool/task-temp-20261011/updater-locale-target-accepted-regression.log` and `.dart_tool/task-temp-20261011/updater-locale-target-accepted-analysis.log`.

## Evidence limits

These results do not establish native installer behavior on a physical device, full visual UI behavior, or Xcode/iOS behavior. The tests and analyzer also cannot distinguish two APKs that share the same version name when release tags and file metadata omit the build code.

## Commands and gate compatibility

All commands used `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011` and `/home/ubuntu/flutter/bin/flutter`:

- `flutter test --no-pub --reporter expanded test/services/app_update_service_test.dart test/services/admin_force_update_settings_test.dart test/widgets/notification_update_narrow_layout_static_test.dart`: **58 passed**, root collected exit **0**.
- `flutter analyze --no-pub lib/core/app_update_ui_copy.dart lib/services/app_update_service.dart test/services/app_update_service_test.dart`: **No issues found**, exit **0**.
- `flutter test --no-pub --reporter expanded test/widgets/force_update_gate_screenshot_test.dart`: **3 passed**, root collected exit **0**; log `.dart_tool/task-temp-20261011/updater-force-gate-compatible-regression.log`.

The gate compatibility check exercised 1280 px, 390 px, and 320 px layouts using the existing widget test. Screenshot capture was not enabled, and no image was produced or reviewed. Its surrounding labels remain page-owned Chinese copy, so this is layout/behavior compatibility, not global bilingual UI acceptance.

The two groups contain **61 distinct passing checks**. The final source review in `updater-integration-audit-20261011.md` found no remaining defect in the reviewed diff; it separately records that matching metadata cannot validate an APK's internal build, signature or contents.
