# Data settings error locale acceptance — 2026-10-11

## Scope and result

Only the existing `test/core/data_settings_ui_copy_test.dart` changed. Production error formatters were not modified. The focused test passed **11 checks**, exit **0**; two-file analysis reported **No issues found**, exit **0** (110.3 seconds).

All commands used `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011` and `/home/ubuntu/flutter/bin/flutter`:

```sh
flutter test --no-pub --reporter expanded test/core/data_settings_ui_copy_test.dart
flutter analyze --no-pub lib/core/data_settings_ui_copy.dart test/core/data_settings_ui_copy_test.dart
```

Logs:

- `.dart_tool/task-temp-20261011/data-settings-ui-copy-locale-regression.log`
- `.dart_tool/task-temp-20261011/data-settings-ui-copy-locale-analysis.log`

## Exercised behavior

- Chinese/English generic and format-specific fallbacks across export, import, file import/migration, data migration, rollback, WebDAV save, upload and restore.
- Rendering a captured API timeout after switching locale; intended 4xx detail remains literal, and 5xx diagnostics use each operation's safe fallback.
- Typed `FormatException`, `SocketException` and `TimeoutException`, plus existing string-based socket/handshake/connection-refused/timed-out classification.
- The actual service's HTTP 401/403/404/500/503 error-string convention for WebDAV upload/restore.
- Safe generic rendering of unexpected diagnostics and credential-bearing URLs. Every credential in the test is synthetic; raw details are not presented.

No behavior defect surfaced in the exercised branches. These checks verify copy and classification. They do not establish network backup success, rollback atomicity, page cancellation/busy recovery, or cross-account import sequencing; those flows retain their separate acceptance requirements.
