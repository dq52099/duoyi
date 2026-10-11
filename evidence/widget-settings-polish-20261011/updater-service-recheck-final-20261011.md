# Updater Service Recheck — Corrected Static Assertions

Date: 2026-10-11

## Correction

Updated only `test/services/admin_force_update_settings_test.dart`. Five gate-copy source assertions now check the actual `AppUpdateUiCopy` method wiring for required title, required description, installer-unavailable message, unsupported-platform title, and notes heading. Each helper is also checked against its exact Chinese and English output. The remaining force-update policy, `PopScope`, and installer assertions remain in place. No production files changed.

The original failed run and report remain unchanged: [original failure log](updater-service-recheck-20261011-logs/admin_force_update_settings_test.log) and [original recheck report](updater-service-recheck-20261011.md).

## Results

- `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter test --no-pub --concurrency=1 --reporter expanded test/services/admin_force_update_settings_test.dart` — **5 passed**, exit code `0`. [Corrected raw output](updater-service-recheck-20261011-logs/admin_force_update_settings_corrected_test.log); [exit code](updater-service-recheck-20261011-logs/admin_force_update_settings_corrected_test.exit-code).
- `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter analyze --no-pub test/services/admin_force_update_settings_test.dart lib/widgets/force_update_gate.dart lib/core/app_update_ui_copy.dart` — **No issues found** (3 items). [Raw output](updater-service-recheck-20261011-logs/admin_force_update_settings_corrected_analyze.log); [exit code](updater-service-recheck-20261011-logs/admin_force_update_settings_corrected_analyze.exit-code).
- The unchanged `app_update_service_test.dart` result from the original recheck remains **48 passed**, exit code `0`.

## Hashes

The admin settings test changed from `df88605216022bda5751972cd398fdac2154c71faad1af3bd3f2d5e3860f16e3` before the correction to `b9f34400a635c272504120c9ef33f8fefc63f6a19dc59673dc4044f27639146d`. Its corrected hash is unchanged across the final test and analysis runs. Before/after records are [corrected-source-test-hashes-before-run.txt](updater-service-recheck-20261011-logs/corrected-source-test-hashes-before-run.txt) and [corrected-source-test-hashes-after-run.txt](updater-service-recheck-20261011-logs/corrected-source-test-hashes-after-run.txt).

Production hashes are unchanged from the original recheck:

| File | SHA-256 |
| --- | --- |
| `lib/widgets/force_update_gate.dart` | `59a4e8684095ae5713233354cee4655a9df68464e8360c95889ca731f6518b6a` |
| `lib/core/app_update_ui_copy.dart` | `7b01fd8466c0a24c7320d1952cdbe328824e05186be908fef6d9661e496084d6` |
| `lib/services/app_update_service.dart` | `8afe4bc6023ddebe5373b45664caa196b14cf81930181e70ebf0ad8256722fc7` |

## Limits

This correction reran only the admin force-update settings suite and analyzed the corrected test plus the gate and copy helper. It did not rerun the passing 48-test updater service suite or the broader project suite. No backend runtime, download/install flow, build, or deployment was exercised.
