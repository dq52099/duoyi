# Todo subtask and detail-save account acceptance — 2026-10-11

This accepts the provider boundary changes only. Frontend callers and retained route/button behavior have separate pending acceptance.

## Changes

- Add, toggle, delete, and reorder subtask entry points capture storage and account generations before taking mutation claims. Optional `expectedAccountDataGeneration` rejects retained callbacks with an old opening account before hydration or claims.
- Locked operations check the captured origin after hydration and before same-ID lookup/mutation. Saves carry the existing `canWrite` predicate through hydration and into the queued write.
- Parent completion recomputation receives the originating account, checks after persistence and synchronous notifications, and keeps audit/reminder operations inside the same origin.
- Detail updates now guard queued saves and recheck after synchronous provider notifications before reminder work. Existing duplicate handling, unconditional claim cleanup, parent completion rules, and public call compatibility are preserved.
- Independent source audit found no remaining provider blocker; see `todo-detail-final-origin-audit-20261011.md`.

## Verification

The serial six-file Flutter regression completed with **76 tests passed, exit 0**. It includes **29 new cases** covering explicit stale origins, same-account reset, account switch during hydration, disposal, queued saves, synchronous notification changes, and released claims across all subtask operations and detail updates. Existing aggregation, Schedule Today, storage safety, batch and recurrence/reminder suites passed in that same run. No property-test iteration is counted as a separate test.

The first four-file analysis returned one test-only missing-braces info. After adding braces, the same scoped analysis returned **No issues found, exit 0**. That edit changes no test semantics. Tests and analysis use the required task `TMPDIR` and `/home/ubuntu/flutter/bin/flutter`.

Logs:
- `.dart_tool/task-temp-20261011/todo-subtask-update-final-regression-20261011.log`
- `.dart_tool/task-temp-20261011/todo-subtask-update-final-analysis-rerun-20261011.log`

Source SHA-256: `76a0e0afaf06b1c39804a4db1033cad66cb0d2208e4d52e65b18cbb6de3d3055` (`lib/providers/todo_provider.dart`). New test SHA-256: `e826941868cbe5c1c77d40759e226d2e0635645eda9e1d8b2620232860727985`.

No device, APK signing, current Web build, deployment, or complete-project acceptance follows from this provider run.
