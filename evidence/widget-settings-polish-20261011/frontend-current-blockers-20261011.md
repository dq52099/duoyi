# Focused frontend analysis — 2026-10-11

## Result

The focused Flutter analysis of five requested frontend files completed in 261.6 seconds and exited with code **1**. The log `.dart_tool/task-temp-20261011/frontend-current-analysis.log` reports **35 issues: 3 errors and 32 infos**.

## Blocking diagnostics

All three errors are `undefined_named_parameter` diagnostics for `key` passed to `_TodayTodoSwipeTile` in `lib/screens/today_screen.dart`:

- Line 326, column 25
- Line 3244, column 9
- Line 3464, column 13

The widget constructor at `today_screen.dart:2432` does not declare a `key` parameter or forward one with `super.key`, so these call sites are rejected by the analyzer.

## Informational diagnostics

- `lib/screens/backup_screen.dart`: 26 `use_build_context_synchronously` infos.
- `lib/screens/notification_history_screen.dart`: 3 `use_build_context_synchronously` infos at lines 4886, 4894, and 4902.
- `lib/screens/today_screen.dart`: one `use_build_context_synchronously` info at line 2524, reported as guarded by an unrelated `mounted` check.
- `lib/screens/today_screen.dart`: two deprecation infos at lines 3403–3404; `ExpansionTileController` is deprecated in favor of `ExpansibleController`.

## Files without diagnostics

The analysis emitted no diagnostics for `lib/widgets/calendar_event_sheet.dart` or `lib/screens/todo_detail_screen.dart`.

This report documents the completed analysis result. No source or test files were changed for this report update.
