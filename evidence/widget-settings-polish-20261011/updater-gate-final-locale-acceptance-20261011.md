# Updater Gate Locale Acceptance

Date: 2026-10-11

## Fixture contract

The mounted regression uses a test-local `AppUpdateService` fixture populated through the existing `debugSetUpdatePolicyForTest` hook: current version `1.1.34`, latest version `1.1.37`, minimum supported version `1.1.34`, and force update enabled. Its download URL is unset, so the install button remains disabled. The fixture returns the exact supplied mixed-language Markdown release notes and uses a `MockClient` that records any request; the acceptance asserts that no request was made.

The test mounts the same provider instance at 320 × 700 with text scale 1.8, then changes the live locale zh → en → zh. At each step it checks the rendered app-owned labels, exact `SelectableText.data`, an unchanged updater policy/state snapshot, and the absence of an enabled install action or framework exception.

The static narrow-layout test now checks that the force gate wires its installer row to `AppUpdateUiCopy.installerLabel()` and that the actual copy renders `安装包` in Chinese and `Installer` in English.

## Results

- `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter test --no-pub --concurrency=1 test/widgets/force_update_gate_screenshot_test.dart` — **4 passed**.
- `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter test --no-pub --concurrency=1 test/widgets/notification_update_narrow_layout_static_test.dart` — **5 passed**.
- `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter analyze --no-pub test/widgets/force_update_gate_screenshot_test.dart test/widgets/notification_update_narrow_layout_static_test.dart lib/widgets/force_update_gate.dart lib/core/app_update_ui_copy.dart` — **No issues found** (4 items).

The first mounted-test attempt exposed a missing `ThemeProvider` in the new fixture. The fixture was updated to provide the same local theme provider used by the existing gate screenshot harness; the production files were not changed. The final serial test run passed.

## SHA-256 of accepted source and tests

| File | SHA-256 |
| --- | --- |
| `lib/widgets/force_update_gate.dart` | `59a4e8684095ae5713233354cee4655a9df68464e8360c95889ca731f6518b6a` |
| `lib/core/app_update_ui_copy.dart` | `7b01fd8466c0a24c7320d1952cdbe328824e05186be908fef6d9661e496084d6` |
| `test/widgets/force_update_gate_screenshot_test.dart` | `35a9c4555e7ad5de0ece4671710525a694ddfd0e7a02ab6e94f8705581212efb` |
| `test/widgets/notification_update_narrow_layout_static_test.dart` | `f35ba37e38984d625de9242e97c9241121b6fd40d87cd1631830f47ec33be96b` |

## Limits

This is focused widget and source acceptance for the current updater gate copy. It does not rerun the historical 58-test updater service acceptance or the broader project suite. The mounted fixture makes no HTTP requests and performs no download or installation. No build, deployment, or screenshot capture was run.
