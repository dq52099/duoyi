# Updater Service Recheck

Date: 2026-10-11. Both tests were run serially with `--concurrency=1` and `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011`.

## Results

- `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter test --no-pub --concurrency=1 --reporter expanded test/services/app_update_service_test.dart` — **48 passed**, exit code `0`. Raw output: [app_update_service_test.log](updater-service-recheck-20261011-logs/app_update_service_test.log); [exit code](updater-service-recheck-20261011-logs/app_update_service_test.exit-code).
- `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter test --no-pub --concurrency=1 --reporter expanded test/services/admin_force_update_settings_test.dart` — **4 passed, 1 failed**, exit code `1`. Raw output: [admin_force_update_settings_test.log](updater-service-recheck-20261011-logs/admin_force_update_settings_test.log); [exit code](updater-service-recheck-20261011-logs/admin_force_update_settings_test.exit-code).

The retained failure is `admin_force_update_settings_test.dart:192`: its source-string assertion expects `force_update_gate.dart` to contain `需要更新后才能继续使用`. The gate now renders this copy through `AppUpdateUiCopy.requiredTitle()`, so the old literal source assertion fails. No test or production source was changed for this recheck.

## SHA-256 before and after

The before and after records are [source-test-hashes-before.txt](updater-service-recheck-20261011-logs/source-test-hashes-before.txt) and [source-test-hashes-after.txt](updater-service-recheck-20261011-logs/source-test-hashes-after.txt). Their hashes match:

| File | SHA-256 |
| --- | --- |
| `lib/core/app_update_ui_copy.dart` | `7b01fd8466c0a24c7320d1952cdbe328824e05186be908fef6d9661e496084d6` |
| `lib/services/app_update_service.dart` | `8afe4bc6023ddebe5373b45664caa196b14cf81930181e70ebf0ad8256722fc7` |
| `test/services/app_update_service_test.dart` | `d5b928ea5d9c1283455290e1c1bd37f930681a6f564633a20ed7bd5cbac592ca` |
| `test/services/admin_force_update_settings_test.dart` | `df88605216022bda5751972cd398fdac2154c71faad1af3bd3f2d5e3860f16e3` |
