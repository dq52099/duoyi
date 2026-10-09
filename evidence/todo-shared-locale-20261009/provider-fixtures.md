# Time audit disposal fixtures — 2026-10-09

Added `test/providers/time_audit_provider_disposal_test.dart` in the assigned
Todo shared locale worktree. The file has 11 test cases: load disposal, save
initialization disposal, four operation-specific in-flight save cases (add,
update, import, and upsert), tombstone-await disposal, direct calls after
disposal, reset and account-generation load races, and a fresh-lifetime save
and notification case.

The controlled SharedPreferences platform store gates `getAll()` and selected
`setValue()` calls. The fixtures assert that invalidated work does not begin
later storage operations, notify listeners, or invoke the local mutation
callback. For an already-started `setValue()`, the storage request can finish
after disposal; the fixture checks suppression of later effects and does not
claim that the write can be rolled back. The deletion fixture similarly lets
the already-started tombstone write finish and asserts that the provider does
not start its follow-up time-entry save.

No test, Dart command, formatter, build, network action, or Git mutation was
run. The fixtures remain unexecuted as requested.
