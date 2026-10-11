# Widget launch platform regression — 2026-10-11

## Prior rooted verification history

The previously completed rooted Flutter regression superseded the earlier static-assertion failures. It completed with **103 tests passed** and exit code **0**, as reported by `.dart_tool/task-temp-20261011/widget-launch-rooted-regression.log` (`00:25 +103: All tests passed!`). The subsequent safe-logging change exposed one obsolete static diagnostic expectation (102 pass, 1 fail); it was corrected and strengthened to forbid raw URI interpolation.

The focused integration analysis is clean: `.dart_tool/task-temp-20261011/widget-launch-integration-final-analysis.log` reports `Analyzing 3 items... No issues found! (ran in 67.1s)`; exit code **0**.

Native Android verification completed successfully. `.dart_tool/task-temp-20261011/widget-launch-native-online-tests.log` ends in `BUILD SUCCESSFUL in 6m 9s`. The produced unit-test report, `build/app/test-results/testDebugUnitTest/TEST-com.duoyi.duoyi.DuoyiWidgetLaunchQueueTest.xml`, reports **5 tests, 0 failures, 0 errors, 0 skipped**.

## Final compatibility checks

The final nine-file widget regression, after the required-call static checks and safe-logging assertion correction, passed **103 tests**, exit code **0**. `.dart_tool/task-temp-20261011/widget-launch-accepted-tests-final.log` ends with `00:30 +103: All tests passed!`. This supersedes the intermediate 102-pass/1-fail rerun.

The final focused Flutter analysis reports **no issues** across 4 items in `.dart_tool/task-temp-20261011/widget-launch-accepted-analysis.log` (`No issues found! (ran in 266.4s)`); exit code **0**.

The requested widget service tests completed with **32 tests passed** and exit code **0**. The run used `/home/ubuntu/flutter/bin/flutter test --no-pub --reporter expanded` with `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011` for:

- `test/services/home_widget_snapshot_test.dart`
- `test/services/widget_publication_test.dart`
- `test/services/widget_quick_todo_persistence_test.dart`

The full output and `COMMAND_EXIT_CODE=0` are recorded in `.dart_tool/task-temp-20261011/widget-launch-compatible-services-final.log`.

## Swift verification status

Both production-extracted Swift Foundation cores passed their fixture suites:

- `.dart_tool/task-temp-20261011/widget-launch-ios-container-final.log` records **23 named snapshot and launch-buffer fixture cases**, ending with `production Swift snapshot core satisfied all fixture assertions`.
- `.dart_tool/task-temp-20261011/widget-launch-ios-timer-final.log` records **19 named timer fixture cases**, ending with `production Swift timer core satisfied all fixture assertions`.

These checks ran in the official `swift:6.2-noble` Docker image with networking disabled and the repository mounted read-only. They execute the Foundation-only production cores extracted from the iOS sources. **Xcode, SwiftUI, WidgetKit, MethodChannel adapters, and device behavior remain unverified.**

An additional display-core verifier was canceled before Swift execution: the image was no longer in the local Docker cache, so the client attempted a fresh pull. Only the verified task-owned Docker client was stopped; no running Swift container existed. `.dart_tool/task-temp-20261011/widget-launch-ios-display-final.log` records that attempt. No display-core pass is claimed, and this does not supersede the two completed core runs above.

## Scope

This report records final widget regression, service compatibility, integration analysis, native Android test, and production-extracted Swift core evidence. The combined Flutter coverage is 135 passing checks in distinct files (103 launch/platform/routing checks and 32 service/persistence checks). No source or test files were changed for this report update; no publishing or deployment was performed.
