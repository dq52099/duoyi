# TodoDetail account-origin test contract

Status: source-only test work. The Flutter test suite, analyzer, and build were
not run during the delivery acceptance window.

## Coverage

`test/screens/todo_detail_account_origin_test.dart` now covers two UI boundaries:

1. A TodoDetail route opened for an old account with a dirty title/notes draft
   and retained subtask toggle/reorder callbacks. The recording provider accepts
   the production `expectedAccountDataGeneration` argument. While the old
   generation is current, both callbacks reach it with the captured origin. The
   account cleanup then clears the old controllers, preserves the device locale
   preference, and loads a new record with the same id. The stale route shows
   only the missing-item state; retained callbacks make no provider calls, and
   the route can pop. Reopening under the new generation can save new title and
   notes.
2. The production `TodayDetailRouter.open` path. A `NavigatorObserver` switches
   accounts in `didPush`, after route construction/push. The test delays the
   next widget pump until replacement same-id data is loaded, placing the
   generation change before TodoDetail's first route frame. The route must show
   the missing-item state instead of either account's title or notes.

The provider test at `test/providers/todo_subtask_account_origin_test.dart`
continues to own hydration, queued-save, and listener-reset coverage. This screen
test only checks callback provenance and route rendering. Related TodoDetail,
router, and provider tests plus the allowed Todo/Today sources were read to align
the harness and API signatures. No production file or other test was edited; no
Search or Habit source file was opened.

## Fixture cleanup

Each widget fixture starts with empty mocked preferences. Teardown unmounts the
widget tree first, disposes the explicitly owned providers, then removes the
`todos` cache entry.

## Execution

No Flutter tests, analyzer, or build were run. A formatting command was not
available in this environment (`dart: command not found`); no Flutter command
was attempted.
