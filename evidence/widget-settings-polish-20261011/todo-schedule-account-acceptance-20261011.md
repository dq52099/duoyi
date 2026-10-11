# Schedule Today account boundary acceptance

## Change

`TodoProvider.scheduleTodoForToday` now captures storage and account generations
before awaiting hydration. Its optional `expectedAccountDataGeneration` lets
a caller bind an action to the account that created the callback. A supplied
stale origin is rejected before ID claims. The origin is checked after
hydration, after saving, after synchronous notification, and before reporting
success after reminder work.

The origin also guards the save queue before hydration, enqueue and queued
execution. This closes the reviewed race where a delayed old action could
persist the new account's unhydrated list. Existing claim cleanup stays
unconditional in `finally`; reset does not clear those claim sets.
Date, due-time and reminder calculation semantics remain covered.

## Executed verification

All commands used
`TMPDIR=/home/ubuntu/duoyi/.dart_tool/task-temp-20261011` and the repository's
`/home/ubuntu/flutter/bin/flutter`.

```sh
flutter test --no-pub --concurrency=1 --reporter expanded \
  test/providers/todo_schedule_account_origin_test.dart \
  test/providers/todo_storage_safety_test.dart \
  test/providers/todo_batch_operations_test.dart \
  test/providers/todo_provider_disposal_test.dart \
  test/providers/todo_recurrence_reminder_test.dart
flutter analyze --no-pub lib/providers/todo_provider.dart \
  test/providers/todo_schedule_account_origin_test.dart
```

The final regression run completed with exit 0: **51 checks passed**, including
11 new account-origin cases. Analysis completed with exit 0 and no issues.
Logs: `todo-schedule-account-final-regression-20261011.log` and
`todo-schedule-account-analysis-20261011.log` under the task temp directory.
An earlier 50-check pass predates the queue guard and is not the final verdict.

The new cases cover same-ID replacement during hydration, storage reset,
disposal, stale explicit origin, save callback/queue/notification invalidation,
awaited and immediate reminder invalidation, successful reminder semantics,
no-wait behavior and claim release. Sol's independent static review closed the
save-queue finding in `todo-schedule-account-fence-review-20261011.md`.

## Remaining integration

AGY owns the pending Today callback change to pass its creation-time origin
and suppress stale feedback. These provider checks do not establish that page
integration or real Android/iOS notification behavior. No build, deployment,
signing or device action was performed for this acceptance batch.
