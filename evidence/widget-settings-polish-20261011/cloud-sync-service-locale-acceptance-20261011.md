# Cloud sync service locale acceptance — 2026-10-11

## Accepted results

The accepted regression runs cover **124 distinct passing tests** across three batches:

| Batch | Tests | Result | Evidence log |
| --- | ---: | --- | --- |
| Cloud sync provider live-locale regression | 50 | Passed | `.dart_tool/task-temp-20261011/cloud-sync-live-locale-accepted-regression.log` |
| Explicit API and widget message locale regressions | 33 | Passed | `.dart_tool/task-temp-20261011/widget-admin-explicit-locale-regression.log` |
| Service compatibility regressions | 41 | Passed | `.dart_tool/task-temp-20261011/service-locale-compatible-regression-20261011.log` |

The 33-test batch covered `admin_response_locale_test.dart`, `widget_action_message_test.dart`, and `widget_action_message_delivery_test.dart`. The 41-test batch covered `cloud_sync_metadata_boundary_test.dart`, `cloud_sync_focus_payload_static_test.dart`, `home_widget_snapshot_test.dart`, `widget_publication_test.dart`, and `widget_quick_todo_persistence_test.dart`.

Static analysis passed for the nine requested files: `No issues found! (ran in 57.3s)`. Evidence: `.dart_tool/task-temp-20261011/cloud-sync-locale-final-analysis.log`.

## Source acceptance

The source audit in [cloud-sync-locale-contract-20261011.md](cloud-sync-locale-contract-20261011.md) records the implementation review:

- Cloud-sync notices retain typed reasons and safe error input, then render in the active locale when read. `CloudSyncProvider` listens for locale changes and removes that listener on disposal.
- `userVisibleApiError` accepts an explicit locale, allowing safe rendering without changing the global locale. Safe server-authored details remain literal.
- Widget sync notices carry typed notice data with frozen sync facts and render when dispatched.

## Acceptance boundary

This is service and regression-test acceptance. Caller-supplied Chinese `localSavedText`, page-owned wrappers and labels, and page layout remain outside the source scope. No UI or device acceptance was performed.

## Commands and superseded runs

All commands used `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011` and `/home/ubuntu/flutter/bin/flutter`.

- Provider: `flutter test --no-pub --reporter expanded test/services/cloud_sync_provider_test.dart`.
- API/widget feedback: `flutter test --no-pub --reporter expanded test/services/admin_response_locale_test.dart test/services/widget_action_message_test.dart test/widgets/widget_action_message_delivery_test.dart`.
- Compatibility: `flutter test --no-pub --reporter expanded test/services/cloud_sync_metadata_boundary_test.dart test/services/cloud_sync_focus_payload_static_test.dart test/services/home_widget_snapshot_test.dart test/services/widget_publication_test.dart test/services/widget_quick_todo_persistence_test.dart`.
- Analysis: `flutter analyze --no-pub lib/main.dart lib/providers/cloud_sync_provider.dart lib/services/api_client.dart lib/services/admin_response_error.dart lib/services/cloud_sync_notice.dart lib/services/widget_action_message.dart test/services/cloud_sync_provider_test.dart test/services/widget_action_message_test.dart test/services/admin_response_locale_test.dart`.

Root collected exit code **0** for the provider and API/widget processes; the compatibility and analysis agents independently returned exit code **0**. The initial provider run did not compile because the new test mistakenly called `ApiClient.close`; cleanup was moved to its injected `MockClient`. A subsequent run exposed outdated source assertions for typed feedback and relocated generated copy. Both intermediate failures are superseded by the accepted 50-test provider run.

The optional `LocalizedUserVisibleApiException` interface preserves getter-only `UserVisibleApiException` implementations. Authored error detail remains literal; unexpected exceptions and server diagnostics retain safe localized fallback. Locale switches neither issue new sync requests nor change pending/retry/account facts, and the frozen widget reason renders in an explicit locale without mutating global locale.
