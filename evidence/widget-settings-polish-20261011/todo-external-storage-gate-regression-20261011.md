# Todo external storage update regression — 2026-10-11

## Behavior

`TodoProvider.runExternalStorageUpdate` reserves write and hydration tails before its first await. Existing saves finish before a backup mutation; the mutation and private reload run in the same queue. New mutations arriving during the draining interval capture the prospective generation, wait, then edit the restored list. Old continuations retain their original generation. Account changes, reset and disposal cancel obsolete work; failed storage operations reload the remaining storage and release the gate without hiding the original error. Concurrent external updates are refused; BackupScreen disables concurrent actions.

Every `_saveToStorage` now captures storage/account origin before hydration and rechecks it in its queued write. Backup callers invoke storage services inside the gate; callbacks must not call the provider or public hydration themselves.

## Verification

The new nine-case suite plus six existing Todo suites passed **85 tests, exit 0**, in one serial run. Existing suites cover subtask origin and aggregation, scheduling origin, storage safety, batch operations and recurrence/reminders. The first nine-case run had two fixture failures because `provider.todos` is sorted for display; assertions now compare membership and select the subtask parent by ID. Persisted order and actual mutation assertions remain intact.

Command: `TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011 /home/ubuntu/flutter/bin/flutter test --no-pub --concurrency=1 --reporter expanded` followed by these seven files under `test/providers/`: `todo_external_storage_update_test.dart`, `todo_subtask_account_origin_test.dart`, `todo_subtask_aggregation_pbt_test.dart`, `todo_schedule_account_origin_test.dart`, `todo_storage_safety_test.dart`, `todo_batch_operations_test.dart`, and `todo_recurrence_reminder_test.dart`.

Log: `.dart_tool/task-temp-20261011/todo-external-storage-full-regression-20261011.log`.

Focused analysis of `lib/providers/todo_provider.dart` and `test/providers/todo_external_storage_update_test.dart` completed with **no issues, exit 0**, in 76.2 seconds. Log: `.dart_tool/task-temp-20261011/todo-external-storage-final-analysis-20261011.log`. Both source hashes below still match the tested files.

The bounded Sol review found no remaining provider blocker after the prospective-generation correction. Final Backup UI/service verification is recorded separately when collected; the visible latest-import Undo still awaits its authorized frontend repair. This report does not claim that UI acceptance, a device run, or a release.

## Source hashes

- `lib/providers/todo_provider.dart`: `1c626af22bf9187ebd6e2c5a38e534640a7e1032ac371f96a0d16b3fbd05f9e8`
- `test/providers/todo_external_storage_update_test.dart`: `c85e0983df9d444dc549fe8c7d24f196b11406e902b6a1d3453f5e244c93c7ee`
